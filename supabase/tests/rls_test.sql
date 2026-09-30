-- Row Level Security and privilege checks (CLAUDE.md: no table ships without
-- RLS policies and a test). Run with `supabase test db` (pgTAP).
--
-- Everything runs in one transaction that is rolled back: it loads fresh demo
-- data and creates a throwaway account for each role, then acts as each one.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(29);

select public.reset_demo_data();

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-00000000000d', 'rls-dispatcher@test.local'),
  ('00000000-0000-4000-8000-00000000000a', 'rls-admin@test.local'),
  ('00000000-0000-4000-8000-00000000000b', 'rls-responder@test.local'),
  ('00000000-0000-4000-8000-00000000000c', 'rls-resident@test.local'),
  ('00000000-0000-4000-8000-00000000000e', 'rls-stranger@test.local');
insert into public.staff (id, display_name, email, role, unit_id) values
  ('00000000-0000-4000-8000-00000000000d', 'Test Dispatcher', 'rls-dispatcher@test.local', 'dispatcher', null),
  ('00000000-0000-4000-8000-00000000000a', 'Test Admin', 'rls-admin@test.local', 'admin', null),
  ('00000000-0000-4000-8000-00000000000b', 'Test Responder', 'rls-responder@test.local', 'responder', 'unit-r05');
-- res-001 sent INC-0147 and has a vulnerable household.
update public.manila_resident
  set auth_user_id = '00000000-0000-4000-8000-00000000000c'
  where manila_resident_id = 'res-001';

-- ------------------------------------------------------------ privileges

select is(
  (select count(*)::int from pg_tables where schemaname = 'public' and not rowsecurity),
  0, 'RLS is on for every public table');
select is(
  (select count(*)::int from information_schema.role_table_grants
    where grantee = 'anon' and table_schema = 'public'),
  0, 'anon has no access to any table or view');
select is(
  (select count(*)::int from information_schema.role_table_grants
    where grantee = 'authenticated' and table_schema = 'public' and privilege_type <> 'SELECT'),
  0, 'signed-in users can only read; every write goes through a checked function');
select ok(
  not has_column_privilege('authenticated', 'public.manila_resident', 'contact_number', 'select'),
  'full contact numbers are not readable by clients');
select ok(
  not has_function_privilege('anon', 'public.assign_unit(text, text, text)', 'execute'),
  'anon cannot call dispatch functions');
select ok(
  not has_function_privilege('authenticated', 'public.reset_demo_data()', 'execute'),
  'demo functions are SQL-editor only');

-- ------------------------------------------------------------ dispatcher

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';

select is((select count(*)::int from public.incident_board where status <> 'resolved'), 6,
  'a dispatcher sees every active incident');
select ok((select count(*) from public.vulnerable_resident_list) > 1,
  'a dispatcher sees the Vulnerable Resident Priority List');
select is((select count(*)::int from public.audit_log), 0,
  'a dispatcher cannot read the audit log');
select is((select count(*)::int from public.staff), 1,
  'a dispatcher sees only their own staff row');
select ok((select bool_and(contact_number like '%•%') from public.resident_profile),
  'resident numbers come masked');
select throws_ok($$ select public.assign_unit('INC-0147', 'unit-r05') $$,
  'P0001', 'unit_not_available', 'a busy unit cannot be assigned');
select lives_ok($$ select public.assign_unit('INC-0147', 'unit-r03') $$,
  'a dispatcher can assign an available unit');
select throws_ok($$ select public.assign_unit('INC-0147', 'unit-r03') $$,
  'P0001', 'already_assigned', 'assigning the same unit twice is refused');
select ok(public.reveal_resident_contact('res-001') not like '%•%',
  'a dispatcher can reveal a full number');

-- ------------------------------------------------------------- responder

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}';

select results_eq(
  $$ select assigned_unit_id from public.incident_board $$,
  $$ values ('unit-r05'::text) $$,
  'a responder sees only the incident assigned to their unit');
select is((select count(*)::int from public.vulnerable_resident_list), 0,
  'a responder cannot see the Vulnerable Resident Priority List');
select throws_ok($$ select public.assign_unit('INC-0148', 'unit-r07') $$,
  'P0001', 'not_allowed', 'a responder cannot dispatch');

-- -------------------------------------------------------------- resident

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';

select results_eq(
  $$ select id from public.incident_board $$,
  $$ values ('INC-0147'::text) $$,
  'a resident sees only their own SOS');
select results_eq(
  $$ select manila_resident_id from public.resident_profile $$,
  $$ values ('res-001'::text) $$,
  'a resident sees only their own profile');
select is((select count(*)::int from public.response_unit), 0,
  'a resident cannot see unit locations');
select throws_ok($$ select public.reveal_resident_contact('res-002') $$,
  'P0001', 'not_allowed', 'a resident cannot reveal other numbers');

-- ------------------------------------------------ signed in, but no role

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000e", "role": "authenticated"}';

select is((select count(*)::int from public.incident_board), 0,
  'an account with no role sees no incidents');
select is((select count(*)::int from public.crowd_report), 0,
  'an account with no role sees no crowd reports');
select is((select count(*)::int from public.resident_profile), 0,
  'an account with no role sees no residents');
select ok((select count(*) from public.weather_alert) > 0,
  'weather advisories are readable by any signed-in account');

-- ----------------------------------------------------------------- admin

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';

select ok((select count(*) from public.staff) >= 3,
  'an admin sees every staff account');
select ok(
  exists (select 1 from public.audit_log
    where account_name = 'Test Dispatcher' and action_type = 'unitAssigned' and target_id = 'INC-0147'),
  'the assignment was written to the audit log under the dispatcher''s name');
select ok(
  exists (select 1 from public.audit_log
    where account_name = 'Test Dispatcher' and action_type = 'contactViewed' and target_id = 'res-001'),
  'revealing a number was written to the audit log');

reset role;
select * from finish();
rollback;
