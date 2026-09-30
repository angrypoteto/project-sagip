-- Move the RLS role helpers out of the API.
--
-- The Supabase security advisor flagged the helpers in public as callable
-- through /rest/v1/rpc by anyone. RLS policies still need them, so they move
-- to a `private` schema that PostgREST does not expose; signed-in users keep
-- EXECUTE (required to evaluate the policies) but cannot call them as RPCs.
--
-- Note for reviewers: the advisor also lists the dispatcher actions
-- (assign_unit, verify_incident, ...) as security-definer functions that
-- signed-in users can call. That is intended: they are the app's write API,
-- and each one checks the caller's role first (see 20260930120200).

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.current_staff_role()
returns text
language sql stable security definer set search_path = ''
as $$ select s.role from public.staff s where s.id = (select auth.uid()) $$;

create or replace function private.is_dispatcher()
returns boolean
language sql stable security definer set search_path = ''
as $$ select coalesce(private.current_staff_role() in ('dispatcher', 'admin'), false) $$;

create or replace function private.is_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$ select coalesce(private.current_staff_role() = 'admin', false) $$;

create or replace function private.current_staff_unit()
returns text
language sql stable security definer set search_path = ''
as $$ select s.unit_id from public.staff s where s.id = (select auth.uid()) $$;

create or replace function private.current_resident_id()
returns text
language sql stable security definer set search_path = ''
as $$ select r.manila_resident_id from public.manila_resident r where r.auth_user_id = (select auth.uid()) $$;

revoke execute on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;

-- Recreate every policy against the private helpers.
drop policy "staff: own row, or all for admins" on public.staff;
create policy "staff: own row, or all for admins" on public.staff
  for select to authenticated
  using (id = (select auth.uid()) or (select private.is_admin()));

drop policy "residents: dispatchers, admins, or self" on public.manila_resident;
create policy "residents: dispatchers, admins, or self" on public.manila_resident
  for select to authenticated
  using ((select private.is_dispatcher()) or auth_user_id = (select auth.uid()));

drop policy "vulnerable list: dispatchers, admins, or own household" on public.vulnerable_member;
create policy "vulnerable list: dispatchers, admins, or own household" on public.vulnerable_member
  for select to authenticated
  using ((select private.is_dispatcher()) or manila_resident_id = (select private.current_resident_id()));

drop policy "units: any staff" on public.response_unit;
create policy "units: any staff" on public.response_unit
  for select to authenticated
  using ((select private.current_staff_role()) is not null);

drop policy "incidents: dispatchers, assigned responders, or the sender" on public.incident_report;
create policy "incidents: dispatchers, assigned responders, or the sender" on public.incident_report
  for select to authenticated
  using (
    (select private.is_dispatcher())
    or (assigned_unit_id is not null and assigned_unit_id = (select private.current_staff_unit()))
    or (manila_resident_id is not null and manila_resident_id = (select private.current_resident_id()))
  );

drop policy "crowd reports: dispatchers, admins, or the author" on public.crowd_report;
create policy "crowd reports: dispatchers, admins, or the author" on public.crowd_report
  for select to authenticated
  using ((select private.is_dispatcher()) or manila_resident_id = (select private.current_resident_id()));

drop policy "dispatch: dispatchers, admins, or the unit" on public.dispatch;
create policy "dispatch: dispatchers, admins, or the unit" on public.dispatch
  for select to authenticated
  using ((select private.is_dispatcher()) or unit_id = (select private.current_staff_unit()));

drop policy "audit log: admins only" on public.audit_log;
create policy "audit log: admins only" on public.audit_log
  for select to authenticated
  using ((select private.is_admin()));

drop function public.is_dispatcher();
drop function public.is_admin();
drop function public.current_staff_unit();
drop function public.current_resident_id();
drop function public.current_staff_role();
