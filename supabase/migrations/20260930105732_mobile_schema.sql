-- Mobile app backend, part 1: tables and columns (plan Phase 2 gaps).
--
-- Adds what the resident and responder apps write and read: the client UUID
-- that makes every phone record arrive once even when it comes by internet,
-- SMS, and a Bluetooth relay (Q31); the phone's capture time on crowd
-- reports (NFR1); the on-scene check (FR8); completion and damage reports;
-- public alerts with per-user read state; 72-hour barangay forecasts;
-- barangays; and data deletion requests (RA 10173).
--
-- Clients still only READ; the next migration adds the checked functions
-- that write.

-- ------------------------------------------------------------ barangays

-- Manila's barangays. Only a sample until the Data role supplies all 897
-- with districts and boundaries; see supabase/README.md for loading them.
create table public.barangay (
  name text primary key,
  district text not null,
  center_latitude double precision check (center_latitude between -90 and 90),
  center_longitude double precision check (center_longitude between -180 and 180),
  boundary extensions.geography(multipolygon, 4326)
);
comment on table public.barangay is
  'Manila barangays (sample of 10 until the full list of 897 with boundaries is loaded).';

insert into public.barangay (name, district, center_latitude, center_longitude) values
  ('Barangay 105', 'Tondo', 14.61972, 120.96706),
  ('Barangay 128', 'Tondo', 14.6258, 120.9718),
  ('Barangay 287', 'Binondo', 14.6003, 120.9745),
  ('Barangay 306', 'Quiapo', 14.5990, 120.9840),
  ('Barangay 412', 'Sampaloc', 14.6091, 120.9925),
  ('Barangay 461', 'Sampaloc', 14.6075, 120.9985),
  ('Barangay 490', 'Sampaloc', 14.6123, 120.9968),
  ('Barangay 560', 'Sampaloc', 14.61103, 121.00012),
  ('Barangay 649', 'Port Area', 14.5869, 120.9690),
  ('Barangay 700', 'Malate', 14.5712, 120.9888);

-- ------------------------------------------------------------ incidents

alter table public.incident_report
  -- Made on the phone; the same SOS by internet, SMS, and relay is stored once.
  add column client_uuid uuid unique,
  add column needs_extra_help boolean not null default false,
  -- The responder's on-scene check (F5, FR8).
  add column real_emergency boolean,
  add column not_real_reason text,
  add column people_found int check (people_found >= 0);

-- ------------------------------------------------------------ crowd reports

alter table public.crowd_report
  add column client_uuid uuid unique,
  -- When the resident pressed Send; never replaced by upload time (NFR1).
  add column captured_at timestamptz not null default now(),
  add column accuracy_m double precision check (accuracy_m >= 0),
  -- What the resident chose; `category` stays the classifier's suggestion.
  add column reported_type text check (reported_type in ('flood', 'fire', 'medical', 'structural'));

update public.crowd_report set captured_at = submitted_at;

create index crowd_report_captured_idx on public.crowd_report (captured_at);
create index crowd_report_resident_idx on public.crowd_report (manila_resident_id, captured_at);

-- ------------------------------------------------------------ completion reports

-- The responder's completion and damage report (F6). The id is made on the
-- phone, so a report sent twice after a reconnect is stored once.
create table public.completion_report (
  report_id uuid primary key,
  incident_id text not null references public.incident_report (incident_id) on delete cascade,
  unit_id text not null references public.response_unit (unit_id) on delete cascade,
  filed_by uuid references public.staff (id) on delete set null,
  captured_at timestamptz not null,
  received_at timestamptz not null default now(),
  outcome text not null check (outcome in ('rescued', 'treated', 'transported', 'noOneFound', 'falseReport')),
  persons_assisted int not null check (persons_assisted >= 0),
  time_on_scene_s int not null default 0 check (time_on_scene_s >= 0),
  houses_damaged int not null default 0 check (houses_damaged >= 0),
  injured int not null default 0 check (injured >= 0),
  missing int not null default 0 check (missing >= 0),
  affected_families int not null default 0 check (affected_families >= 0),
  notes text,
  unique (incident_id, unit_id)
);
comment on table public.completion_report is 'Completion and damage reports from responders (F6); feeds NDRRMC reports.';
create index completion_report_unit_idx on public.completion_report (unit_id, captured_at desc);

-- ------------------------------------------------------------ alerts

-- Alerts shown to residents (R7, R8, FR14): PAGASA warnings, relayed
-- PHIVOLCS advisories, EFCOS river levels, and MDRRMD notices.
create table public.public_alert (
  alert_id text primary key default ('alert-' || gen_random_uuid()::text),
  source text not null check (source in ('pagasa', 'phivolcs', 'efcos', 'mdrrmd')),
  level text not null check (level in ('info', 'warning', 'critical')),
  title text not null check (length(btrim(title)) > 0),
  body text not null,
  guidance text[] not null default '{}',
  -- Empty means all of Manila.
  barangays text[] not null default '{}',
  issued_at timestamptz not null default now(),
  expires_at timestamptz,
  is_simulated boolean not null default false
);
comment on table public.public_alert is 'Alerts for residents (FR14). Expired alerts are hidden.';
create index public_alert_issued_idx on public.public_alert (issued_at desc);

create table public.alert_read (
  alert_id text not null references public.public_alert (alert_id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (alert_id, user_id)
);
comment on table public.alert_read is 'Which account has opened which alert (the unread dot on R7).';

-- ------------------------------------------------------------ forecasts

-- 72-hour risk per barangay from the LSTM + KDE model (FR4, plan 10.5).
create table public.barangay_forecast (
  forecast_id bigint generated always as identity primary key,
  barangay text not null,
  district text not null,
  issued_at timestamptz not null,
  valid_until timestamptz not null,
  flood_risk text not null check (flood_risk in ('low', 'moderate', 'high')),
  fire_risk text not null check (fire_risk in ('low', 'moderate', 'high')),
  surge_risk text not null check (surge_risk in ('low', 'moderate', 'high')),
  model_version text,
  -- True while the model runs on a simulated live feed (thesis scope).
  is_simulated boolean not null default false,
  check (valid_until > issued_at)
);
comment on table public.barangay_forecast is '72-hour barangay risk forecasts (FR4). The latest row per barangay is current.';
create index barangay_forecast_latest_idx on public.barangay_forecast (barangay, issued_at desc);

-- ------------------------------------------------------------ data deletion

create table public.data_deletion_request (
  request_id bigint generated always as identity primary key,
  manila_resident_id text not null
    references public.manila_resident (manila_resident_id) on delete cascade,
  requested_at timestamptz not null default now(),
  handled_at timestamptz,
  handled_by uuid references public.staff (id) on delete set null
);
comment on table public.data_deletion_request is 'Residents asking MDRRMD to delete their data (RA 10173).';

-- ------------------------------------------------------------ access

grant select on
  public.barangay, public.completion_report, public.public_alert,
  public.alert_read, public.barangay_forecast, public.data_deletion_request
to authenticated;

alter table public.barangay enable row level security;
alter table public.completion_report enable row level security;
alter table public.public_alert enable row level security;
alter table public.alert_read enable row level security;
alter table public.barangay_forecast enable row level security;
alter table public.data_deletion_request enable row level security;

create policy "barangays: any signed-in user" on public.barangay
  for select to authenticated
  using (true);

create policy "completion reports: dispatchers, admins, or the unit" on public.completion_report
  for select to authenticated
  using ((select private.is_dispatcher()) or unit_id = (select private.current_staff_unit()));

create policy "alerts: any signed-in user" on public.public_alert
  for select to authenticated
  using (true);

create policy "alert reads: own only" on public.alert_read
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "forecasts: any signed-in user" on public.barangay_forecast
  for select to authenticated
  using (true);

create policy "deletion requests: admins, or the resident" on public.data_deletion_request
  for select to authenticated
  using ((select private.is_admin()) or manila_resident_id = (select private.current_resident_id()));

alter publication supabase_realtime add table
  public.completion_report, public.public_alert, public.alert_read, public.barangay_forecast;
