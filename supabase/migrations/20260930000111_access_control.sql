-- Access control (FR10, NFR4): role helpers, Row Level Security on every
-- table, column grants, and read views.
--
-- Clients (anon and authenticated) can only READ. Every change goes through
-- the security-definer functions in the next migration, which check the
-- caller's role first. The Vulnerable Resident Priority List and resident
-- details are visible to dispatchers and admins only; the audit log to admins
-- only; responders see only incidents assigned to their unit.

-- ------------------------------------------------------------ role helpers

create or replace function public.current_staff_role()
returns text
language sql stable security definer set search_path = ''
as $$ select s.role from public.staff s where s.id = (select auth.uid()) $$;

create or replace function public.is_dispatcher()
returns boolean
language sql stable security definer set search_path = ''
as $$ select coalesce(public.current_staff_role() in ('dispatcher', 'admin'), false) $$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$ select coalesce(public.current_staff_role() = 'admin', false) $$;

create or replace function public.current_staff_unit()
returns text
language sql stable security definer set search_path = ''
as $$ select s.unit_id from public.staff s where s.id = (select auth.uid()) $$;

create or replace function public.current_resident_id()
returns text
language sql stable security definer set search_path = ''
as $$ select r.manila_resident_id from public.manila_resident r where r.auth_user_id = (select auth.uid()) $$;

-- ------------------------------------------------------------ grants

-- Start from nothing, then grant only SELECT to signed-in users. New tables
-- also start with no client access; each migration grants what it needs.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;

grant select on
  public.staff, public.vulnerable_member, public.response_unit,
  public.incident_report, public.incident_event, public.crowd_report,
  public.dispatch, public.weather_alert, public.audit_log
to authenticated;

-- Residents: every column except the full contact number (NFR4).
grant select (
  manila_resident_id, auth_user_id, fullname, contact_masked,
  barangay, district, consent_given_at, updated_at
) on public.manila_resident to authenticated;

-- ------------------------------------------------------------ RLS

alter table public.staff enable row level security;
alter table public.manila_resident enable row level security;
alter table public.vulnerable_member enable row level security;
alter table public.response_unit enable row level security;
alter table public.incident_report enable row level security;
alter table public.incident_event enable row level security;
alter table public.crowd_report enable row level security;
alter table public.dispatch enable row level security;
alter table public.weather_alert enable row level security;
alter table public.audit_log enable row level security;

create policy "staff: own row, or all for admins" on public.staff
  for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));

create policy "residents: dispatchers, admins, or self" on public.manila_resident
  for select to authenticated
  using ((select public.is_dispatcher()) or auth_user_id = (select auth.uid()));

create policy "vulnerable list: dispatchers, admins, or own household" on public.vulnerable_member
  for select to authenticated
  using ((select public.is_dispatcher()) or manila_resident_id = (select public.current_resident_id()));

create policy "units: any staff" on public.response_unit
  for select to authenticated
  using ((select public.current_staff_role()) is not null);

create policy "incidents: dispatchers, assigned responders, or the sender" on public.incident_report
  for select to authenticated
  using (
    (select public.is_dispatcher())
    or (assigned_unit_id is not null and assigned_unit_id = (select public.current_staff_unit()))
    or (manila_resident_id is not null and manila_resident_id = (select public.current_resident_id()))
  );

create policy "timeline: whoever can see the incident" on public.incident_event
  for select to authenticated
  using (exists (select 1 from public.incident_report i where i.incident_id = incident_event.incident_id));

create policy "crowd reports: dispatchers, admins, or the author" on public.crowd_report
  for select to authenticated
  using ((select public.is_dispatcher()) or manila_resident_id = (select public.current_resident_id()));

create policy "dispatch: dispatchers, admins, or the unit" on public.dispatch
  for select to authenticated
  using ((select public.is_dispatcher()) or unit_id = (select public.current_staff_unit()));

create policy "weather: any signed-in user" on public.weather_alert
  for select to authenticated
  using (true);

create policy "audit log: admins only" on public.audit_log
  for select to authenticated
  using ((select public.is_admin()));

-- ------------------------------------------------------------ views
-- security_invoker: the caller's RLS and column grants apply.

-- One row per incident in the shape of the app's Incident.fromJson.
create view public.incident_board with (security_invoker = true) as
select
  i.incident_id as id,
  i.origin, i.channel, i.status, i.suggested_type, i.emergency_type,
  i.latitude, i.longitude, i.barangay, i.district, i.address, i.accuracy_m,
  i.captured_at, i.received_at, i.manila_resident_id, i.people_count, i.note,
  i.vulnerable, i.account_verified, i.mock_location, i.verification_method,
  i.assigned_unit_id, i.suggestion_overridden, i.override_reason,
  i.false_report, i.resolved_at,
  coalesce(
    (select array_agg(c.report_id order by c.submitted_at)
       from public.crowd_report c where c.incident_id = i.incident_id),
    '{}'
  ) as crowd_report_ids,
  coalesce(
    (select jsonb_agg(jsonb_build_object(
        'kind', e.kind, 'at', e.at, 'actor_name', e.actor_name, 'detail', e.detail
      ) order by e.at, e.event_id)
       from public.incident_event e where e.incident_id = i.incident_id),
    '[]'::jsonb
  ) as events
from public.incident_report i;

-- Residents with their household, in the shape of Resident.fromJson.
-- contact_number here is the masked form.
create view public.resident_profile with (security_invoker = true) as
select
  r.manila_resident_id, r.fullname, r.contact_masked as contact_number,
  r.barangay, r.district, r.consent_given_at, r.updated_at,
  coalesce(
    (select jsonb_agg(jsonb_build_object(
        'label', m.label, 'vulnerability_types', m.vulnerability_types, 'notes', m.notes
      ) order by m.member_id)
       from public.vulnerable_member m where m.manila_resident_id = r.manila_resident_id),
    '[]'::jsonb
  ) as household
from public.manila_resident r;

-- The Vulnerable Resident Priority List: consented residents with members.
create view public.vulnerable_resident_list with (security_invoker = true) as
select p.*
from public.resident_profile p
where p.consent_given_at is not null and jsonb_array_length(p.household) > 0;

grant select on public.incident_board, public.resident_profile, public.vulnerable_resident_list
  to authenticated;

-- ------------------------------------------------------------ realtime

-- manila_resident is left out on purpose: clients cannot read its full
-- contact_number column, so realtime could not deliver its rows. Screens
-- refresh resident details when vulnerable_member changes instead.
alter publication supabase_realtime add table
  public.incident_report, public.incident_event, public.crowd_report,
  public.response_unit, public.weather_alert, public.audit_log,
  public.vulnerable_member;
