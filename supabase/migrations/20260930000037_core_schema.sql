-- S.A.G.I.P. core schema (thesis Figure 3.6, plus the gaps listed in plan Q14-Q17).
--
-- Value columns use the exact names of the app's Dart enums (for example
-- 'pendingVerification', 'enRoute', 'crowdCluster') so no mapping is needed.
-- IDs are readable text ('INC-0147', 'unit-r03', 'res-001') so rows are easy
-- to find and edit in the Supabase Table Editor.

create extension if not exists postgis with schema extensions;

-- Staff accounts (dispatchers, administrators, responders). One table with a
-- role column instead of separate admin and dispatcher tables (plan Q8).
create table public.staff (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null,
  email text not null unique,
  role text not null check (role in ('dispatcher', 'admin', 'responder')),
  unit_id text,
  created_at timestamptz not null default now()
);
comment on table public.staff is 'MDRRMD accounts: dispatcher, admin, or responder (FR10).';

create sequence public.resident_number_seq start 100;

create table public.manila_resident (
  manila_resident_id text primary key
    default ('res-' || lpad(nextval('public.resident_number_seq')::text, 3, '0')),
  auth_user_id uuid unique references auth.users (id) on delete set null,
  fullname text not null,
  -- Full number: readable only through reveal_resident_contact(), which logs
  -- the access (NFR4). Clients read contact_masked instead.
  contact_number text not null,
  contact_masked text generated always as (
    left(regexp_replace(contact_number, '\D', '', 'g'), 4) || ' ••• ' ||
    right(regexp_replace(contact_number, '\D', '', 'g'), 4)
  ) stored,
  barangay text not null,
  district text not null,
  consent_given_at timestamptz,
  updated_at timestamptz not null default now()
);
comment on table public.manila_resident is 'Registered residents (MANILA_RESIDENT).';

-- One resident can register several vulnerable household members (plan Q14).
create table public.vulnerable_member (
  member_id bigint generated always as identity primary key,
  manila_resident_id text not null
    references public.manila_resident (manila_resident_id) on delete cascade,
  label text not null,
  vulnerability_types text[] not null check (
    cardinality(vulnerability_types) > 0
    and vulnerability_types <@ array['seniorCitizen', 'pwd', 'pregnant', 'other']
  ),
  notes text,
  created_at timestamptz not null default now()
);
comment on table public.vulnerable_member is
  'Vulnerable Resident Priority List entries (VULNERABLE_PROFILE). Kept only with consent (NFR4).';

create table public.response_unit (
  unit_id text primary key,
  call_sign text not null unique,
  unit_type text not null check (unit_type in ('ambulance', 'rescueBoat', 'rescueTeam')),
  station text not null,
  crew_size int not null check (crew_size > 0),
  status text not null default 'available' check (status in ('available', 'enRoute', 'onScene')),
  last_latitude double precision,
  last_longitude double precision,
  last_location_at timestamptz,
  current_incident_id text
);
comment on table public.response_unit is 'Ambulances, rescue boats, and rescue teams (FR9).';

alter table public.staff
  add constraint staff_unit_fk foreign key (unit_id)
  references public.response_unit (unit_id) on delete set null;

create sequence public.incident_number_seq start 200;

create table public.incident_report (
  incident_id text primary key
    default ('INC-' || lpad(nextval('public.incident_number_seq')::text, 4, '0')),
  origin text not null check (origin in ('sos', 'crowdCluster')),
  channel text not null check (channel in ('app', 'sms', 'bleRelay', 'webForm')),
  status text not null default 'pendingVerification' check (status in (
    'pendingVerification', 'unverified', 'confirmed', 'assigned', 'enRoute', 'onScene', 'resolved'
  )),
  suggested_type text check (suggested_type in ('flood', 'fire', 'medical', 'structural')),
  emergency_type text check (emergency_type in ('flood', 'fire', 'medical', 'structural')),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  barangay text not null,
  district text not null,
  address text,
  accuracy_m double precision,
  -- When the phone captured it; never replaced by upload time (NFR1).
  captured_at timestamptz not null default now(),
  received_at timestamptz not null default now(),
  manila_resident_id text references public.manila_resident (manila_resident_id) on delete set null,
  people_count int check (people_count > 0),
  note text,
  vulnerable text[] not null default '{}' check (
    vulnerable <@ array['seniorCitizen', 'pwd', 'pregnant', 'other']
  ),
  account_verified boolean not null default false,
  mock_location boolean not null default false,
  verification_method text check (verification_method in ('callback', 'smsReply', 'onScene')),
  assigned_unit_id text references public.response_unit (unit_id) on delete set null,
  suggestion_overridden boolean not null default false,
  override_reason text,
  false_report boolean not null default false,
  resolved_at timestamptz
);
comment on table public.incident_report is 'SOS requests and confirmed crowd-report clusters (INCIDENT_REPORT).';
create index incident_report_status_idx on public.incident_report (status);

alter table public.response_unit
  add constraint response_unit_incident_fk foreign key (current_incident_id)
  references public.incident_report (incident_id) on delete set null;

-- Timeline of each incident, shown in the dashboard drawer.
create table public.incident_event (
  event_id bigint generated always as identity primary key,
  incident_id text not null references public.incident_report (incident_id) on delete cascade,
  kind text not null check (kind in (
    'received', 'smsCheckSent', 'smsReplyReceived', 'verified', 'typeConfirmed',
    'assigned', 'enRoute', 'onScene', 'resolved', 'markedFalseReport'
  )),
  at timestamptz not null default now(),
  actor_name text,
  detail text
);
create index incident_event_incident_idx on public.incident_event (incident_id, at);

create sequence public.crowd_report_number_seq start 300;

create table public.crowd_report (
  report_id text primary key
    default ('rep-' || nextval('public.crowd_report_number_seq')::text),
  manila_resident_id text references public.manila_resident (manila_resident_id) on delete set null,
  incident_id text references public.incident_report (incident_id) on delete set null,
  description text not null check (length(btrim(description)) > 0),
  category text check (category in ('flood', 'fire', 'medical', 'structural')),
  category_confidence double precision check (category_confidence between 0 and 1),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  barangay text not null,
  district text not null,
  source text not null default 'app' check (source in ('app', 'webForm')),
  submitted_at timestamptz not null default now()
);
comment on table public.crowd_report is 'Hazard reports; confirmed only as a DBSCAN cluster (FR7, FR15).';
create index crowd_report_submitted_idx on public.crowd_report (submitted_at);

-- One row per assignment (DISPATCH, Figure 3.6b). Source for response-time analytics.
create table public.dispatch (
  dispatch_id bigint generated always as identity primary key,
  incident_id text not null references public.incident_report (incident_id) on delete cascade,
  unit_id text not null references public.response_unit (unit_id) on delete cascade,
  assigned_by uuid references public.staff (id) on delete set null,
  suggestion_overridden boolean not null default false,
  override_reason text,
  route text,
  dispatch_time timestamptz not null default now(),
  arrival_time timestamptz,
  completion_time timestamptz
);
create index dispatch_incident_idx on public.dispatch (incident_id);

create table public.weather_alert (
  alert_id bigint generated always as identity primary key,
  signal_level int not null default 0 check (signal_level between 0 and 5),
  rainfall_intensity numeric(6, 1) not null default 0 check (rainfall_intensity >= 0),
  storm_surge_advisory text,
  barangay text,
  issued_at timestamptz not null default now(),
  is_simulated boolean not null default false
);
comment on table public.weather_alert is 'PAGASA conditions (WEATHER_ALERT). Latest row is current.';

create table public.audit_log (
  log_id bigint generated always as identity primary key,
  "timestamp" timestamptz not null default now(),
  account_id text not null,
  account_name text not null,
  account_role text not null check (account_role in ('resident', 'responder', 'dispatcher', 'admin', 'system')),
  action_type text not null check (action_type in (
    'verified', 'markedFalseReport', 'typeConfirmed', 'unitAssigned', 'unitReassigned',
    'statusChanged', 'resolved', 'smsCheckSent', 'contactViewed'
  )),
  target_table text not null,
  target_id text not null,
  detail text
);
comment on table public.audit_log is 'Every dispatch action, status change, and verification (FR11).';
create index audit_log_time_idx on public.audit_log ("timestamp" desc);
