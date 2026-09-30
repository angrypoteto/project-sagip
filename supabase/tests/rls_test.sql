-- Row Level Security and privilege checks (CLAUDE.md: no table ships without
-- RLS policies and a test). Run with `supabase test db` (pgTAP).
--
-- Everything runs in one transaction that is rolled back: it loads fresh demo
-- data and creates a throwaway account for each role, then acts as each one.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(158);

select public.reset_demo_data();

insert into auth.users (id, email, phone) values
  ('00000000-0000-4000-8000-00000000000d', 'rls-dispatcher@test.local', null),
  ('00000000-0000-4000-8000-00000000000a', 'rls-admin@test.local', null),
  ('00000000-0000-4000-8000-00000000000b', 'rls-responder@test.local', null),
  ('00000000-0000-4000-8000-00000000000c', 'rls-resident@test.local', '639170004821'),
  ('00000000-0000-4000-8000-00000000000e', 'rls-stranger@test.local', null),
  -- Signs in by phone with res-002's number; not linked yet.
  ('00000000-0000-4000-8000-00000000000f', null, '639180003310'),
  -- A new number with no resident record.
  ('00000000-0000-4000-8000-000000000010', null, '639185550101'),
  -- A second responder with no unit yet (A2 roster checks).
  ('00000000-0000-4000-8000-000000000011', 'rls-responder2@test.local', null);
insert into public.staff (id, display_name, email, role, unit_id) values
  ('00000000-0000-4000-8000-00000000000d', 'Test Dispatcher', 'rls-dispatcher@test.local', 'dispatcher', null),
  ('00000000-0000-4000-8000-00000000000a', 'Test Admin', 'rls-admin@test.local', 'admin', null),
  ('00000000-0000-4000-8000-00000000000b', 'Test Responder', 'rls-responder@test.local', 'responder', 'unit-r05'),
  ('00000000-0000-4000-8000-000000000011', 'Test Responder Two', 'rls-responder2@test.local', 'responder', null);
-- res-001 sent INC-0147 and has a vulnerable household.
update public.manila_resident
  set auth_user_id = '00000000-0000-4000-8000-00000000000c'
  where manila_resident_id = 'res-001';
-- R-05's open dispatch (INC-0142) carries a route, as the dashboard saves it.
update public.dispatch
  set route = '_p~iF~ps|U', route_plan = '{"seconds": 300, "meters": 2000, "steps": []}'
  where incident_id = 'INC-0142' and completion_time is null;

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
  not has_function_privilege('anon', 'public.assign_unit(text, text, text, jsonb)', 'execute'),
  'anon cannot call dispatch functions');
select ok(
  not has_function_privilege('anon',
    'public.log_routing_run(text, text, numeric, text, int, int, int, date)', 'execute'),
  'anon cannot write the routing timing log');
select ok(not has_function_privilege('anon', 'public.set_setting(text, jsonb)', 'execute'),
  'anon cannot change settings');
select ok(not has_function_privilege('anon', 'public.analytics_report(timestamptz, timestamptz)', 'execute'),
  'anon cannot read analytics');
select ok(not has_function_privilege('anon', 'public.save_unit(text, text, text, text, int)', 'execute'),
  'anon cannot change units');
select ok(not has_function_privilege('anon', 'public.admin_create_staff(text, text, text, text)', 'execute'),
  'anon cannot create accounts');
select ok(
  not has_function_privilege('authenticated', 'public.reset_demo_data()', 'execute'),
  'demo functions are SQL-editor only');
select ok(
  not has_function_privilege('anon',
    'public.submit_sos(uuid, timestamptz, double precision, double precision, double precision, text, text, boolean)',
    'execute'),
  'anon cannot send an SOS');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and has_function_privilege('anon', p.oid, 'execute')),
  0, 'anon cannot run any private helper');
select ok(
  not has_table_privilege('authenticated', 'public.sms_log', 'select')
  and not has_table_privilege('anon', 'public.sms_log', 'select'),
  'the SMS log (full numbers) is not readable by any client');

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
select throws_ok(
  $$ select public.assign_unit('INC-0146', 'unit-a05', null, '{"polyline": 5}'::jsonb) $$,
  'P0001', 'invalid_value', 'a malformed route is refused');
select lives_ok(
  $$ select public.assign_unit('INC-0146', 'unit-a05', null,
       '{"polyline": "_p~iF~ps|U", "seconds": 412, "meters": 2310, "steps": [], "compute_ms": 4.2}'::jsonb) $$,
  'a dispatcher can assign with the unit''s road route');
select ok(
  (select route = '_p~iF~ps|U' and route_plan->>'seconds' = '412' and not route_plan ? 'polyline'
     from public.dispatch where incident_id = 'INC-0146' and completion_time is null),
  'the dispatch record keeps the route');
select lives_ok(
  $$ select public.log_routing_run('suggestions', 'web', 12.5, 'INC-0146', 9, 9296, 23716, '2026-09-30') $$,
  'a dispatcher can log a Dijkstra run');
select throws_ok($$ select public.log_routing_run('guess', 'web', 1) $$,
  'P0001', 'invalid_value', 'an unknown run kind is refused');
select is((select count(*)::int from public.routing_run), 0,
  'a dispatcher cannot read the timing log');
select is((select count(*)::int from public.app_setting where category = 'priority'), 8,
  'a dispatcher reads the priority weights');
select results_eq(
  $$ select priority_score, priority_severity from public.incident_board where id = 'INC-0146' $$,
  $$ values (58::numeric, 'high'::text) $$,
  'the board scores a confirmed cluster: 40, plus 18 for 9 minutes waiting');
select results_eq(
  $$ select priority_score, priority_severity from public.incident_board where id = 'INC-0147' $$,
  $$ values (88::numeric, 'critical'::text) $$,
  'the board scores an SOS with a vulnerable household: 50 + 30 + 8 for 4.2 minutes');
select throws_ok($$ select public.set_setting('priority.sos', '60') $$,
  'P0001', 'not_allowed', 'a dispatcher cannot change settings');
select throws_ok($$ select public.analytics_report(now() - interval '1 day', now()) $$,
  'P0001', 'not_allowed', 'a dispatcher cannot read analytics (admins only)');
select throws_ok($$ select public.save_unit(null, 'R-20', 'rescueTeam', 'Paco', 5) $$,
  'P0001', 'not_allowed', 'a dispatcher cannot add units (admins only)');
select throws_ok($$ select public.admin_create_staff('x@test.local', 'X', 'dispatcher') $$,
  'P0001', 'not_allowed', 'a dispatcher cannot create accounts (admins only)');

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
select is(public.my_assignments()->0->'route'->>'polyline', '_p~iF~ps|U',
  'the responder''s job carries the route from the dispatch');
select lives_ok($$ select public.log_routing_run('route', 'android', 3.2, 'INC-0142') $$,
  'a responder can log a Dijkstra run');

-- -------------------------------------------------------------- resident

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';

select results_eq(
  $$ select id from public.incident_board order by id $$,
  $$ values ('INC-0118'::text), ('INC-0147'::text) $$,
  'a resident sees only their own SOS requests');
select results_eq(
  $$ select manila_resident_id from public.resident_profile $$,
  $$ values ('res-001'::text) $$,
  'a resident sees only their own profile');
select is((select count(*)::int from public.response_unit), 0,
  'a resident cannot see unit locations');
select throws_ok($$ select public.reveal_resident_contact('res-002') $$,
  'P0001', 'not_allowed', 'a resident cannot reveal other numbers');
select throws_ok($$ select public.log_routing_run('route', 'android', 3.2) $$,
  'P0001', 'not_allowed', 'a resident cannot write the timing log');
select is((select count(*)::int from public.app_setting), 0,
  'a resident cannot read settings');

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
select is(
  (select count(*)::int from public.routing_run
    where account_id in ('00000000-0000-4000-8000-00000000000d', '00000000-0000-4000-8000-00000000000b')),
  2, 'an admin reads the timing log');
select lives_ok($$ select public.set_setting('priority.sos', '60') $$,
  'an admin can change a priority weight');
select is((select priority_score from public.incident_board where id = 'INC-0147'), 98::numeric,
  'a new weight changes the score at once');
select throws_ok($$ select public.set_setting('priority.waiting_per_minute', '500') $$,
  'P0001', 'invalid_value', 'a weight outside its range is refused');
select throws_ok($$ select public.set_setting('priority.high_at', '90') $$,
  'P0001', 'invalid_value', 'High cannot go above Critical');
select throws_ok($$ select public.set_setting('priority.sos', '"sixty"') $$,
  'P0001', 'invalid_value', 'a setting keeps its type');
select throws_ok($$ select public.set_setting('priority.nope', '1') $$,
  'P0001', 'not_found', 'an unknown setting is refused');
select ok(
  exists (select 1 from public.audit_log
           where account_name = 'Test Admin' and action_type = 'settingChanged'
             and target_id = 'priority.sos' and detail = '50 → 60'),
  'the change is in the audit log (FR11)');
-- The demo timeline: dispatch 122 s (INC-0139), 266 s (INC-0142), 541 s
-- (INC-0144), plus the two assignments made above at now(): 251 s
-- (INC-0147) and 400 s (INC-0146). Verified after 131 s and 146 s; on scene
-- after 842 s (INC-0139).
select results_eq(
  $$ select (r->>'incidents')::int, (r->>'sos')::int, (r->>'median_dispatch_s')::numeric,
            (r->>'avg_verify_s')::numeric, (r->>'median_response_s')::numeric
       from (select public.analytics_report(now() - interval '1 day', now() + interval '1 minute') r) x $$,
  $$ values (6, 4, 266::numeric, 138.5::numeric, 842::numeric) $$,
  'analytics: counts, median dispatch, verification, and response times from the timeline');
select is(
  (select jsonb_array_length(public.analytics_report(now() - interval '1 day', now() + interval '1 minute') -> 'routing')),
  2, 'analytics include the Dijkstra timings (suggestions and routes)');
select throws_ok($$ select public.analytics_report(now(), now() - interval '1 day') $$,
  'P0001', 'invalid_value', 'a period that ends before it starts is refused');
select is(public.save_unit(null, ' r-20 ', 'rescueTeam', 'Paco station', 5), 'unit-r20',
  'an admin can add a unit (call sign tidied, id from it)');
select throws_ok($$ select public.save_unit(null, 'r-03', 'ambulance', 'Tondo station', 3) $$,
  'P0001', 'already_exists', 'a call sign already in use is refused');
select throws_ok($$ select public.save_unit(null, 'R-21', 'ambulance', 'Tondo station', 0) $$,
  'P0001', 'invalid_value', 'a crew of zero is refused');
select lives_ok($$ select public.save_unit('unit-r20', 'R-20', 'rescueTeam', 'Pandacan station', 6) $$,
  'an admin can edit a unit');
select throws_ok($$ select public.retire_unit('unit-r05') $$,
  'P0001', 'unit_not_available', 'a unit on a job cannot be retired');
select lives_ok($$ select public.set_responder_unit('00000000-0000-4000-8000-000000000011', 'unit-r20') $$,
  'an admin can put a responder on a unit');
select throws_ok($$ select public.set_responder_unit('00000000-0000-4000-8000-00000000000d', 'unit-r20') $$,
  'P0001', 'invalid_value', 'only responders go on the roster');
select lives_ok($$ select public.retire_unit('unit-r20') $$, 'an admin can retire a free unit');
select ok(
  (select retired_at is not null from public.response_unit where unit_id = 'unit-r20')
  and (select unit_id is null from public.staff where id = '00000000-0000-4000-8000-000000000011'),
  'retiring a unit takes its responders off it');
select throws_ok($$ select public.assign_unit('INC-0149', 'unit-r20') $$,
  'P0001', 'unit_not_available', 'a retired unit is never dispatched');
select throws_ok($$ select public.set_responder_unit('00000000-0000-4000-8000-000000000011', 'unit-r20') $$,
  'P0001', 'invalid_value', 'nobody goes on a retired unit');
select lives_ok($$ select public.restore_unit('unit-r20') $$, 'an admin can restore a retired unit');
select is(
  (select string_agg(action_type, ',' order by log_id) from public.audit_log
    where account_name = 'Test Admin' and action_type in ('unitAdded', 'unitEdited', 'unitRetired', 'unitRestored', 'rosterChanged')),
  'unitAdded,unitEdited,rosterChanged,unitRetired,unitRestored',
  'every unit and roster change is in the audit log (FR11)');

-- A1 accounts.
select is(
  length(public.admin_create_staff(' New.Dispatcher@Test.local ', 'New Dispatcher', 'dispatcher') ->> 'temporary_password'),
  12, 'an admin creates an account and gets a 12-character temporary password once');
select throws_ok($$ select public.admin_create_staff('new.dispatcher@test.local', 'Again', 'dispatcher') $$,
  'P0001', 'already_exists', 'an email already in use is refused');
select throws_ok($$ select public.admin_create_staff('not-an-email', 'X', 'dispatcher') $$,
  'P0001', 'invalid_value', 'a malformed email is refused');
select throws_ok($$ select public.admin_set_staff_active('00000000-0000-4000-8000-00000000000a', false) $$,
  'P0001', 'own_account', 'an admin cannot deactivate their own account');
select lives_ok(
  $$ select public.admin_set_staff_active((select id from public.staff where email = 'new.dispatcher@test.local'), false) $$,
  'an admin can deactivate an account');
select set_config('request.jwt.claims',
  json_build_object('sub', (select id from public.staff where email = 'new.dispatcher@test.local'),
                    'role', 'authenticated')::text, true);
select is((select count(*)::int from public.incident_board), 0,
  'a deactivated account loses its access at once');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select ok(
  length(public.admin_reset_password((select id from public.staff where email = 'new.dispatcher@test.local')) ->> 'temporary_password') = 12,
  'an admin can reset a password (a new temporary one)');
select throws_ok($$ select public.admin_reset_password('00000000-0000-4000-8000-00000000000a') $$,
  'P0001', 'own_account', 'an admin changes their own password on D11, not here');
select lives_ok(
  $$ select public.admin_update_staff((select id from public.staff where email = 'new.dispatcher@test.local'),
       'N. Dispatcher', 'dispatcher') $$,
  'an admin can rename an account');
select lives_ok(
  $$ select public.admin_set_staff_active((select id from public.staff where email = 'new.dispatcher@test.local'), true) $$,
  'an admin can reactivate an account');
select lives_ok($$ select public.admin_set_resident_suspended('res-001', true) $$,
  'an admin can suspend a resident account');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select throws_ok(
  $$ select public.submit_crowd_report(gen_random_uuid(), now(), 'Flood', 'flood', 14.6, 120.99, 5, null, null) $$,
  'P0001', 'account_suspended', 'a suspended resident cannot send crowd reports');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select lives_ok($$ select public.admin_set_resident_suspended('res-001', false) $$,
  'an admin can lift a suspension');
select is(
  (select string_agg(action_type, ',' order by log_id) from public.audit_log
    where account_name = 'Test Admin' and action_type in ('accountCreated', 'accountUpdated',
      'accountDeactivated', 'accountReactivated', 'passwordReset', 'residentSuspended', 'residentRestored')),
  'accountCreated,accountDeactivated,passwordReset,accountUpdated,accountReactivated,residentSuspended,residentRestored',
  'every account change is in the audit log (FR11)');

-- ------------------------------------------- resident: phone app (part 5)

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';

select is(public.link_resident(), 'res-001',
  'a signed-in resident finds their own record');
select lives_ok(
  $$ select public.submit_sos('00000000-0000-4000-8000-0000000005a1', now() - interval '5 seconds',
       14.6091, 120.9925, 8, 'Barangay 412', 'Sampaloc', false) $$,
  'a resident can send an SOS');
select is(
  public.submit_sos('00000000-0000-4000-8000-0000000005a1', now(), 14.6, 120.99, 8, null, null, false),
  (select incident_id from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000005a1'),
  'sending the same SOS again returns the same incident');
select is(
  (select count(*)::int from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000005a1'),
  1, 'the same SOS is stored once');
select ok(
  (select captured_at < received_at and status = 'pendingVerification'
          and vulnerable @> array['pwd', 'seniorCitizen']
     from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000005a1'),
  'the SOS is Pending Verification, keeps the capture time, and carries the household''s vulnerable types');
select is(jsonb_array_length(public.my_sos()), 3,
  'my_sos lists the resident''s SOS requests');
select ok(not (public.my_sos()->0 ? 'mock_location'),
  'the mock-location flag is never sent back to the resident');
select lives_ok(
  $$ select public.add_sos_details('00000000-0000-4000-8000-0000000005a1', 'flood', 3, true, 'Water inside') $$,
  'a resident can add details to their SOS');
select throws_ok(
  $$ select public.submit_crowd_report(gen_random_uuid(), now(), 'Flood', 'flood', 14.40, 121.20, 10, null, null) $$,
  'P0001', 'outside_manila', 'a report outside Manila is refused (FR15)');
select lives_ok(
  $$ select public.submit_crowd_report(gen_random_uuid(), now(), 'Flood ' || g, 'flood',
       14.595 + g * 0.002, 120.980, 10, null, null) from generate_series(1, 5) g $$,
  'five reports in an hour are accepted');
select throws_ok(
  $$ select public.submit_crowd_report(gen_random_uuid(), now(), 'Flood 6', 'flood', 14.620, 120.980, 10, null, null) $$,
  'P0001', 'rate_limited', 'a sixth report within the hour is refused');
select is(
  (select count(*)::int from jsonb_array_elements(public.my_crowd_reports()) r where r->>'stage' = 'checking'),
  5, 'new reports wait for nearby reports (Checking)');
select is(
  (select string_agg(r->>'stage', ',' order by r->>'server_id')
     from jsonb_array_elements(public.my_crowd_reports()) r where r->>'server_id' like 'rep-1900%'),
  'resolved,notConfirmed', 'past reports show Resolved and Not confirmed');
select lives_ok(
  $$ select public.save_vulnerable_member(null, 'Tita Rosa', array['pregnant'], null) $$,
  'a consenting resident can add a household member');
select is(
  (select jsonb_array_length(household) from public.resident_profile),
  2, 'the household now has two members');
select throws_ok(
  $$ select public.save_vulnerable_member(null, 'X', array['alien'], null) $$,
  'P0001', 'invalid_value', 'an unknown vulnerability type is refused');
select lives_ok($$ select public.withdraw_consent() $$, 'a resident can withdraw consent');
select ok(
  (select consent_given_at is null and jsonb_array_length(household) = 0 from public.resident_profile),
  'withdrawing consent deletes the household list');
select throws_ok(
  $$ select public.save_vulnerable_member(null, 'Lolo', array['seniorCitizen'], null) $$,
  'P0001', 'not_allowed', 'adding a member needs consent');
select throws_ok($$ select public.accept_assignment('INC-0142') $$,
  'P0001', 'not_allowed', 'a resident cannot act as a responder');
select is((select count(*)::int from public.completion_report), 0,
  'a resident cannot read completion reports');
select lives_ok($$ select public.request_data_deletion() $$,
  'a resident can ask for their data to be deleted');

-- --------------------------------------- another resident, linked by phone

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000f", "role": "authenticated"}';

select is(public.link_resident(), 'res-002',
  'signing in with a number MDRRMD already has links that record');
select is(
  (select count(*)::int from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000005a1'),
  0, 'another resident cannot see that SOS');
select throws_ok(
  $$ select public.add_sos_details('00000000-0000-4000-8000-0000000005a1', 'fire', 1, false, null) $$,
  'P0001', 'not_found', 'another resident cannot change that SOS');
select throws_ok(
  $$ select public.submit_sos('00000000-0000-4000-8000-0000000005a1', now(), 14.6, 120.99, 5, null, null, false) $$,
  'P0001', 'not_allowed', 'another resident cannot reuse that SOS id');
select is((select count(*)::int from public.data_deletion_request), 0,
  'another resident cannot see the deletion request');

-- ------------------------------------------------ a new number, registering

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-000000000010", "role": "authenticated"}';

select ok(public.link_resident() is null, 'a new number has no resident record');
select throws_ok(
  $$ select public.submit_sos(gen_random_uuid(), now(), 14.6, 120.99, 5, null, null, false) $$,
  'P0001', 'not_allowed', 'an unregistered number cannot send an SOS');
select ok(public.register_resident('Leo Cruz', 'Barangay 461', 'Sampaloc') like 'res-%',
  'a new number can register');
select ok(
  (select contact_number = '0918 ••• 0101' and barangay = 'Barangay 461' from public.resident_profile),
  'the new record has the verified number (masked) and the barangay');

-- ------------------------------------------------ responder: phone app (part 5)

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}';

select throws_ok($$ select public.accept_assignment('INC-0147') $$,
  'P0001', 'not_allowed', 'a responder cannot take another unit''s incident');
select throws_ok($$ select public.set_unit_status('available') $$,
  'P0001', 'finish_report_first', 'a unit on a job cannot go Available before the report');
select lives_ok($$ select public.mark_on_scene('INC-0142', now()) $$,
  'a responder can mark arrival');
select is((select status from public.response_unit where unit_id = 'unit-r05'), 'onScene',
  'the unit is On scene');
select is((select r->>'status' from jsonb_array_elements(public.my_assignments()) r), 'onScene',
  'my_assignments shows the job On scene');
select throws_ok($$ select public.confirm_on_scene('INC-0142', false, null, 0, now()) $$,
  'P0001', 'invalid_value', '"not a real emergency" needs a reason (FR8)');
select lives_ok($$ select public.confirm_on_scene('INC-0142', true, null, 1, now()) $$,
  'a responder can confirm a real emergency');
select lives_ok(
  $$ select public.submit_completion_report('00000000-0000-4000-8000-0000000007c1', 'INC-0142', now(),
       'transported', 1, 900, 0, 0, 0, 1, 'Taken to hospital') $$,
  'a responder can file the completion report');
select ok(
  (select status = 'resolved' from public.incident_report where incident_id = 'INC-0142')
  and (select status = 'available' and current_incident_id is null from public.response_unit where unit_id = 'unit-r05'),
  'filing the report resolves the incident and frees the unit');
select lives_ok(
  $$ select public.submit_completion_report('00000000-0000-4000-8000-0000000007c1', 'INC-0142', now(),
       'transported', 1, 900, 0, 0, 0, 1, 'Taken to hospital') $$,
  'sending the same report again is accepted');
select is((select count(*)::int from public.completion_report), 1,
  'the report is stored once, and the unit sees only its own reports');
select throws_ok($$ select public.set_unit_status('onScene') $$,
  'P0001', 'no_assignment', 'On scene needs an assignment');
select lives_ok($$ select public.update_unit_location(14.5750, 120.9880, now()) $$,
  'a responder can share the unit''s position');
select lives_ok($$ select public.update_unit_location(14.5000, 120.9000, now() - interval '1 minute') $$,
  'an older position is accepted');
select is((select last_latitude from public.response_unit where unit_id = 'unit-r05'), 14.5750::double precision,
  'but an older position does not move the unit back');
select is(jsonb_array_length(public.my_unit_history()), 1,
  'my_unit_history lists the finished job');

-- ------------------------------------------------ any signed-in account

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000e", "role": "authenticated"}';

select is((select count(*)::int from public.my_alerts where not read), 4,
  'alerts are readable by any signed-in account, all unread');
select lives_ok($$ select public.mark_alert_read('alert-pagasa-rain') $$, 'an alert can be marked read');
select is((select count(*)::int from public.my_alerts where read), 1, 'the read state is kept');
select ok((select count(*) from public.barangay_forecast) > 0, 'forecasts are readable');
select throws_ok(
  $$ select public.submit_crowd_report(gen_random_uuid(), now(), 'Flood', null, 14.6, 120.99, 5, null, null) $$,
  'P0001', 'not_allowed', 'an account with no role cannot send a report');

-- ----------------------------------------------------------------- admin (part 5)

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';

select ok(
  exists (select 1 from public.incident_board i
           join public.incident_report r on r.incident_id = i.id
          where r.client_uuid = '00000000-0000-4000-8000-0000000005a1' and i.status = 'pendingVerification'),
  'the resident''s SOS is on the board at once (FR8)');
select ok(
  exists (select 1 from public.audit_log
           where account_name = 'Test Responder' and target_id = 'INC-0142'
             and action_type in ('statusChanged', 'resolved')),
  'the responder''s status changes are in the audit log under their name (FR11)');
select is((select count(*)::int from public.alert_read), 0,
  'an admin cannot see other accounts'' read state');
select is((select count(*)::int from public.data_deletion_request), 1,
  'an admin sees the deletion request');

-- ------------------------------------------------ Tier 2: SOS by SMS

reset role;
select ok(
  not has_function_privilege('authenticated',
    'public.intake_sms_sos(text, uuid, timestamptz, double precision, double precision, double precision, boolean)', 'execute')
  and not has_function_privilege('anon',
    'public.intake_sms_sos(text, uuid, timestamptz, double precision, double precision, double precision, boolean)', 'execute'),
  'only the gateway (service role) can file an SMS SOS');
select is(
  public.intake_sms_sos('+63 917 000 4821', '00000000-0000-4000-8000-0000000005b1',
    now() - interval '2 minutes', 14.6090, 120.9920, 12, false) ->> 'known',
  'true', 'an SMS SOS from a registered number finds the resident');
select ok(
  (select channel = 'sms' and manila_resident_id = 'res-001' and account_verified
          and status = 'pendingVerification' and captured_at = now() - interval '2 minutes'
     from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000005b1'),
  'it is on the board at once as an SMS SOS with its capture time (FR8)');
select is(
  public.intake_sms_sos('09170004821', '00000000-0000-4000-8000-0000000005b1',
    now(), 14.6, 120.99, 12, false) ->> 'duplicate',
  'true', 'the same SOS texted twice is stored once');
select is(
  public.intake_sms_sos('09995550000', '00000000-0000-4000-8000-0000000005b2',
    now() - interval '1 minute', 14.5869, 120.9690, 20, true) ->> 'known',
  'false', 'an SOS from an unknown number still reaches the board');
select ok(
  (select not account_verified and manila_resident_id is null and mock_location
          and barangay <> 'Not known'
     from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000005b2'),
  'marked not account-verified, with the nearest barangay and the mock-location flag');
select throws_ok($$ select public.intake_sms_sos('0917', gen_random_uuid(), now()) $$,
  'P0001', 'invalid_value', 'a sender without a full number is refused');

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';

select ok(
  public.submit_sos('00000000-0000-4000-8000-0000000005b2', now(), 14.5869, 120.9690, 20, null, null, true) like 'INC-%',
  'the app''s copy of an SOS texted from another SIM is accepted');
select ok(
  (select manila_resident_id = 'res-001' and account_verified and channel = 'sms'
     from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000005b2'),
  'and attaches the resident to the same SOS');

reset role;
update public.manila_resident set suspended_at = now() where manila_resident_id = 'res-001';
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
-- (A separate statement, so the check below sees the new row.)
select public.submit_sos('00000000-0000-4000-8000-0000000005c1', now(), 14.6091, 120.9925, 8, null, null, false);
select ok(
  (select not account_verified from public.incident_report
    where client_uuid = '00000000-0000-4000-8000-0000000005c1'),
  'a suspended resident''s SOS still arrives (FR8), not account-verified');

reset role;
select * from finish();
rollback;
