-- Row Level Security and privilege checks (CLAUDE.md: no table ships without
-- RLS policies and a test). Run with `supabase test db` (pgTAP).
--
-- Everything runs in one transaction that is rolled back: it loads fresh demo
-- data and creates a throwaway account for each role, then acts as each one.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(277);

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

-- ------------------------------------------------ web form (W1 to W3)

reset role;
select ok(
  not has_function_privilege('anon',
    'public.submit_crowd_report(uuid, timestamptz, text, text, double precision, double precision, double precision, text, text, text)', 'execute')
  and not has_function_privilege('anon', 'public.my_report_quota()', 'execute'),
  'anon cannot send a report or read a quota: the web form needs a signed-in resident (FR15)');

set local role authenticated;
-- res-002, linked by phone above, has sent no reports.
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000f", "role": "authenticated"}';

select is(public.my_report_quota() - 'resets_at',
  '{"limit": 5, "used": 0, "remaining": 5, "suspended": false}'::jsonb,
  'a resident starts the hour with the full report quota');
select ok(
  public.submit_crowd_report('00000000-0000-4000-8000-0000000006a1', now(), 'Baha sa kanto', 'flood',
    14.6003, 120.9745, null, 'Barangay 287', 'Binondo', 'webForm') like 'rep-%',
  'a resident can send a report from the web form');
select ok(
  (select source = 'webForm' and incident_id is null from public.crowd_report
    where client_uuid = '00000000-0000-4000-8000-0000000006a1'),
  'it is stored as a web form report and is not confirmed on its own (FR7, FR15)');
select is(
  (select r->>'source' from jsonb_array_elements(public.my_crowd_reports()) r
    where r->>'client_id' = '00000000-0000-4000-8000-0000000006a1'),
  'webForm', 'the resident''s list says which channel sent it');
select is((public.my_report_quota() ->> 'remaining')::int, 4, 'the quota counts it');
select throws_ok(
  $$ select public.submit_crowd_report(gen_random_uuid(), now(), 'Flood', 'flood', 14.6003, 120.9745, null, null, null, 'sos') $$,
  'P0001', 'invalid_value', 'an unknown channel is refused');
select is(
  public.submit_crowd_report('00000000-0000-4000-8000-0000000006a1', now(), 'Again', 'flood',
    14.6003, 120.9745, null, null, null, 'webForm'),
  (select report_id from public.crowd_report where client_uuid = '00000000-0000-4000-8000-0000000006a1'),
  'sending the same web report again returns the same report');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select lives_ok($$ select public.set_setting('reports.per_hour', '1') $$,
  'an admin sets the hourly report limit on A3');
select throws_ok($$ select public.set_setting('reports.per_hour', '0') $$,
  'P0001', 'invalid_value', 'the limit cannot be turned off');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000f", "role": "authenticated"}';
select throws_ok(
  $$ select public.submit_crowd_report(gen_random_uuid(), now(), 'Second', null, 14.6003, 120.9745, null, null, null, 'webForm') $$,
  'P0001', 'rate_limited', 'the new limit applies to the next report');
select ok(
  (select (q ->> 'remaining')::int = 0 and (q ->> 'limit')::int = 1 and q ->> 'resets_at' is not null
     from public.my_report_quota() q),
  'the quota shows none left and when the next one frees up');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select throws_ok($$ select public.my_report_quota() $$,
  'P0001', 'not_allowed', 'staff accounts have no report quota');

-- ------------------------------------- threshold engine and the rest of A3

reset role;
select ok(
  has_function_privilege('anon', 'public.client_config()', 'execute')
  and not has_function_privilege('anon', 'public.simulate_weather(int, numeric, numeric)', 'execute'),
  'anyone may read the hotline and gateway number; anon cannot simulate weather');

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is((select count(*)::int from public.alert_delivery), 0,
  'a resident cannot read the alert delivery log');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select is(
  (select count(*) filter (where channel = 'app' and status = 'sent')::text || ','
       || count(*) filter (where status = 'simulated')::text from public.alert_delivery),
  '4,12', 'a dispatcher reads the log: sample alerts are in the app and never sent outside it');
select throws_ok($$ select public.simulate_weather(3, 35, 2.5) $$,
  'P0001', 'not_allowed', 'a dispatcher cannot simulate weather');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select throws_ok($$ select public.simulate_weather(3, 35, 2.5) $$,
  'P0001', 'not_allowed', 'simulated weather needs simulation mode');
select throws_ok($$ select public.set_setting('demo.simulation', '1') $$,
  'P0001', 'invalid_value', 'a switch stays a switch');
select lives_ok($$ select public.set_setting('demo.simulation', 'true') $$,
  'an admin turns simulation mode on');
select throws_ok($$ select public.simulate_weather(9, 35, 2.5) $$,
  'P0001', 'invalid_value', 'a wind signal above 5 is refused');
-- The sample reading is signal 2 and 18 mm/hr, with no surge height.
select lives_ok($$ select public.simulate_weather(3, 35, 2.5) $$,
  'an admin simulates a typhoon reading');
select results_eq(
  $$ select hazard, level, is_simulated from public.public_alert
      where weather_alert_id = (select max(alert_id) from public.weather_alert) order by hazard $$,
  $$ values ('rainfall'::text, 'critical'::text, true), ('signal', 'critical', true), ('surge', 'critical', true) $$,
  'each reading that crossed its threshold raised an alert, marked simulated (FR5)');
select is(
  (select string_agg(d.channel || ':' || d.status, ',' order by d.channel)
     from public.alert_delivery d join public.public_alert a using (alert_id)
    where a.hazard = 'surge' and a.weather_alert_id = (select max(alert_id) from public.weather_alert)),
  'app:sent,facebook:simulated,push:simulated,sms:simulated',
  'a simulated alert is shown in the apps and never texted or posted');
select ok(
  exists (select 1 from public.audit_log
           where account_name = 'Test Admin' and action_type = 'weatherSimulated'
             and detail = 'Signal 3, 35 mm/hr, surge 2.5 m'),
  'the simulated reading is in the audit log (FR11)');
select public.simulate_weather(4, 40, 3);
select is(
  (select count(*)::int from public.public_alert
    where weather_alert_id = (select max(alert_id) from public.weather_alert)),
  0, 'a reading at the same level raises nothing new');
select public.simulate_weather(0, 2, null);
select is(
  (select count(*)::int from public.public_alert
    where hazard is not null and (expires_at is null or expires_at > now())),
  0, 'when conditions ease, the automatic alerts expire');
select public.simulate_weather(1, 2, null);
select public.simulate_weather(3, 2, null);
select is(
  (select string_agg(level, ',') from public.public_alert
    where hazard = 'signal' and (expires_at is null or expires_at > now())),
  'critical', 'a warning that becomes critical is replaced, not doubled');

select throws_ok($$ select public.set_setting('alerts.rainfall_warning', '40') $$,
  'P0001', 'invalid_value', 'a warning threshold cannot go above its critical one');
select lives_ok($$ select public.set_setting('alerts.rainfall_warning', '20') $$,
  'an admin changes an alert threshold');
select lives_ok($$ select public.set_setting('channels.sms', 'false') $$,
  'an admin switches a channel off');
select lives_ok($$ select public.set_setting('contact.sms_gateway', '"0917 555 0199"') $$,
  'an admin sets the SMS gateway number');
select throws_ok($$ select public.set_setting('contact.sms_gateway', '"12345"') $$,
  'P0001', 'invalid_value', 'the gateway must be a Philippine mobile number');
select lives_ok($$ select public.set_setting('contact.hotline', '"(02) 8527-0000"') $$,
  'an admin sets the hotline');
select throws_ok($$ select public.set_setting('contact.hotline', '"call us"') $$,
  'P0001', 'invalid_value', 'a hotline needs digits');

-- A real reading (not simulated), as the PAGASA feed will insert it.
reset role;
insert into public.weather_alert (signal_level, rainfall_intensity) values (0, 22);
select is(
  (select string_agg(d.channel || ':' || d.status, ',' order by d.channel)
     from public.alert_delivery d join public.public_alert a using (alert_id)
    where a.hazard = 'rainfall' and not a.is_simulated),
  'app:sent,facebook:off,push:queued,sms:off',
  'a real alert waits on each channel that is on; a switched-off channel is logged as off (FR6)');
select is(
  (select level || ': ' || title from public.public_alert where hazard = 'rainfall' and not is_simulated),
  'warning: Heavy rainfall warning', 'with the new threshold (20), 22 mm/hr is a warning');

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is(public.client_config(),
  '{"hotline": "(02) 8527-0000", "sms_gateway": "+639175550199"}'::jsonb,
  'the apps read the hotline and the gateway number');

-- ------------------------------------------------ the alert sender (FR6)

reset role;
select ok(
  not has_function_privilege('authenticated', 'public.claim_alert_deliveries()', 'execute')
  and not has_function_privilege('authenticated', 'public.alert_sms_recipients(text)', 'execute')
  and not has_function_privilege('authenticated', 'public.alert_sms_budget()', 'execute')
  and not has_function_privilege('authenticated',
        'public.finish_alert_delivery(bigint, text, int, int, int, text)', 'execute')
  and has_function_privilege('service_role', 'public.claim_alert_deliveries()', 'execute'),
  'only the sender (service role) can claim deliveries, list numbers, or record outcomes');

-- An MDRRMD alert for one barangay, with SMS switched back on.
update public.app_setting set value = 'true' where key = 'channels.sms';
insert into public.public_alert (alert_id, source, level, title, body, barangays)
values ('alert-test-sms', 'mdrrmd', 'warning', 'Flooding on Dapitan St', 'Avoid the area.',
        array['Barangay 412']);
create temp table __claim as
  select (select count(*)::int from public.alert_delivery
           where status = 'queued' and channel <> 'app') as waiting,
         public.claim_alert_deliveries() as claimed;
select ok(
  (select waiting >= 2 and jsonb_array_length(claimed) = waiting from __claim),
  'the sender claims every queued delivery');
select is(
  (select string_agg(c ->> 'channel', ',' order by c ->> 'channel')
     from __claim, jsonb_array_elements(claimed) c
    where c -> 'alert' ->> 'alert_id' = 'alert-test-sms'),
  'push,sms', 'with the alert to send (the switched-off channel is not claimed)');
select is(
  (select count(*)::int from public.alert_delivery where status = 'queued'),
  0, 'claimed deliveries are marked as being sent');
select is(jsonb_array_length(public.claim_alert_deliveries()), 0,
  'a second run claims nothing, so nothing is sent twice');
select ok(
  (select cardinality(public.alert_sms_recipients('alert-test-sms')) > 0
      and cardinality(public.alert_sms_recipients('alert-test-sms'))
          = (select count(distinct contact_number)::int from public.manila_resident
              where barangay = 'Barangay 412')
      and cardinality(public.alert_sms_recipients('alert-test-sms'))
          < (select count(distinct contact_number)::int from public.manila_resident)),
  'an alert for one barangay texts only its registered residents');
select lives_ok(
  $$ select public.finish_alert_delivery(
       (select delivery_id from public.alert_delivery
         where alert_id = 'alert-test-sms' and channel = 'sms'), 'sent', 3, 3, 0, null) $$,
  'the sender records the outcome');
select throws_ok(
  $$ select public.finish_alert_delivery(
       (select delivery_id from public.alert_delivery
         where alert_id = 'alert-test-sms' and channel = 'sms'), 'sent', 3, 3, 0, null) $$,
  'P0001', 'not_found', 'an outcome is recorded once');
select throws_ok(
  $$ select public.finish_alert_delivery(
       (select delivery_id from public.alert_delivery
         where alert_id = 'alert-test-sms' and channel = 'push'), 'queued') $$,
  'P0001', 'invalid_value', 'only a final outcome can be recorded');
select is(public.alert_sms_budget(), '{"cap": 500, "sent_today": 3, "left": 497}'::jsonb,
  'the daily cap counts the texts sent today');

-- ------------------------------------------- advisories from the dashboard

select ok(
  not has_function_privilege('anon', 'public.issue_alert(text, text, text, text, text[], text[])', 'execute')
  and not has_function_privilege('anon', 'public.end_alert(text)', 'execute'),
  'anon cannot issue or end an advisory');

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select throws_ok(
  $$ select public.issue_alert('mdrrmd', 'warning', 'Flooding', 'Avoid the area.') $$,
  'P0001', 'not_allowed', 'a resident cannot issue an advisory');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select public.set_setting('demo.simulation', 'false');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select ok(
  public.issue_alert('phivolcs', 'info', ' Taal Volcano advisory ', 'Light ashfall may reach Manila.',
    array['Wear a face mask.', '  ', 'Keep windows closed.'], array['Barangay 412', 'Barangay 412']) like 'alert-%',
  'a dispatcher can relay an advisory');
select ok(
  (select source = 'phivolcs' and level = 'info' and title = 'Taal Volcano advisory'
          and guidance = array['Wear a face mask.', 'Keep windows closed.']
          and barangays = array['Barangay 412'] and not is_simulated and expires_at is null
     from public.public_alert where title = 'Taal Volcano advisory'),
  'it is stored tidied: blank steps dropped, each barangay once');
select is(
  (select string_agg(d.channel || ':' || d.status, ',' order by d.channel)
     from public.alert_delivery d join public.public_alert a using (alert_id)
    where a.title = 'Taal Volcano advisory'),
  'app:sent,facebook:off,push:queued,sms:queued',
  'it is in the apps at once and queued on the channels that are on (FR6)');
select throws_ok(
  $$ select public.issue_alert('mdrrmd', 'warning', '   ', 'Avoid the area.') $$,
  'P0001', 'invalid_value', 'an advisory needs a title');
select throws_ok(
  $$ select public.issue_alert('mdrrmd', 'urgent', 'Flooding', 'Avoid the area.') $$,
  'P0001', 'invalid_value', 'an unknown level is refused');
select throws_ok(
  $$ select public.issue_alert('mdrrmd', 'warning', 'Flooding', 'Avoid the area.', '{}', array['Barangay 9999']) $$,
  'P0001', 'invalid_value', 'an unknown barangay is refused');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is(
  (select count(*)::int from public.my_alerts where title = 'Taal Volcano advisory' and not read),
  1, 'residents see the advisory in the app');
select throws_ok(
  $$ select public.end_alert((select alert_id from public.public_alert where title = 'Taal Volcano advisory')) $$,
  'P0001', 'not_allowed', 'a resident cannot end an advisory');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select lives_ok(
  $$ select public.end_alert((select alert_id from public.public_alert where title = 'Taal Volcano advisory')) $$,
  'a dispatcher can end an advisory');
select lives_ok(
  $$ select public.end_alert((select alert_id from public.public_alert where title = 'Taal Volcano advisory')) $$,
  'ending it again does nothing');
select throws_ok($$ select public.end_alert('alert-nope') $$,
  'P0001', 'not_found', 'an unknown alert cannot be ended');
select is(
  (select count(*)::int from public.my_alerts where title = 'Taal Volcano advisory'),
  0, 'an ended advisory is no longer shown');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select public.set_setting('demo.simulation', 'true');
select public.issue_alert('mdrrmd', 'critical', 'Evacuate Baseco', 'Drill only.');
select ok(
  (select a.is_simulated
      and (select bool_and(d.status = case when d.channel = 'app' then 'sent' else 'simulated' end)
             from public.alert_delivery d where d.alert_id = a.alert_id)
     from public.public_alert a where a.title = 'Evacuate Baseco'),
  'in simulation mode an advisory is simulated: in the apps, never texted or posted');
select is(
  (select string_agg(action_type || ' ' || detail, '; ' order by log_id) from public.audit_log
    where action_type in ('alertIssued', 'alertEnded')),
  'alertIssued info: Taal Volcano advisory; alertEnded Taal Volcano advisory; alertIssued critical: Evacuate Baseco (simulated)',
  'issuing and ending are in the audit log (FR11)');

-- ------------------------------------------- incident type classifier (FR12)

select ok(
  not has_table_privilege('anon', 'public.classifier_model', 'select')
  and not has_function_privilege('authenticated', 'private.classify_report(text)', 'execute'),
  'anon cannot read the model; clients cannot call the classifier directly');

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is((select count(*)::int from public.classifier_model), 0,
  'residents cannot read the model');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select is((select string_agg(model_id, ',') from public.classifier_model where is_active), 'v1-sample',
  'dispatchers see which model is active');
select throws_ok(
  $$ update public.classifier_model set min_confidence = 0 where model_id = 'v1-sample' $$,
  '42501', null, 'no client can change the model');
reset role;

-- The same cases as packages/shared/test/fixtures/classifier_reference.json.
select is(
  (select count(*)::int
     from (values
    (E'BAHA NA SA ESPAÑA', 'flood', 0.910643, true),
    (E'sunog sunog sunog', 'fire', 0.986092, true),
    (E'may sunog\nat makapal na usok', 'fire', 0.955552, true),
    (E'5 katao naipit sa 2nd floor, gumuho ang pader', 'structural', 0.940744, true),
    (E'nahimatay sa baha', 'flood', 0.821821, true),
    (E'An elderly neighbor is having difficulty breathing and is very pale', 'medical', 0.976859, true),
    (E'', 'fire', 0.271026, false),
    (E'asdf qwerty zxcv', 'fire', 0.271026, false)
     ) as ref(description, label, confidence, tagged)
     cross join lateral private.classify_report(ref.description) c
    where c.category = ref.label
      and abs(c.confidence - ref.confidence) < 0.00001
      and c.sure = ref.tagged),
  8, 'the database gives the same types and probabilities as the exported model');

insert into public.crowd_report (description, reported_type, latitude, longitude, barangay, district) values
  ('Baha na po dito, hanggang bewang ang tubig', null, 14.5712, 120.9888, 'Barangay 700', 'Malate'),
  ('zzzz qqqq', null, 14.5612, 120.9788, 'Barangay 700', 'Malate'),
  ('Gumuho ang pader, nakaharang sa kalsada', 'fire', 14.5512, 120.9688, 'Barangay 700', 'Malate');
select ok(
  (select category = 'flood' and category_confidence >= 0.5 and reported_type is null
     from public.crowd_report where description = 'Baha na po dito, hanggang bewang ang tubig'),
  'a new report is tagged from its description (FR12)');
select ok(
  (select category is null and category_confidence is null
     from public.crowd_report where description = 'zzzz qqqq'),
  'a description the model cannot place is left untagged');
select ok(
  (select category = 'structural' and reported_type = 'fire'
     from public.crowd_report where description = 'Gumuho ang pader, nakaharang sa kalsada'),
  'the tag does not replace what the resident chose');

insert into public.crowd_report (description, latitude, longitude, barangay, district) values
  ('May sunog dito, makapal ang usok', 14.58690, 120.96900, 'Barangay 649', 'Port Area'),
  ('Nasusunog ang bodega, kumakalat ang apoy', 14.58695, 120.96905, 'Barangay 649', 'Port Area'),
  ('Fire po, malaki na ang apoy', 14.58700, 120.96910, 'Barangay 649', 'Port Area');
select is(
  (select i.suggested_type || ' ' || i.status || ' ' || count(*)
     from public.crowd_report r join public.incident_report i using (incident_id)
    where r.description in ('May sunog dito, makapal ang usok',
                            'Nasusunog ang bodega, kumakalat ang apoy',
                            'Fire po, malaki na ang apoy')
    group by i.suggested_type, i.status),
  'fire confirmed 3',
  'three tagged reports within 50 m become one confirmed incident of that type (FR7, FR12)');

update public.classifier_model set is_active = false where model_id = 'v1-sample';
insert into public.crowd_report (description, latitude, longitude, barangay, district) values
  ('Baha na naman dito sa amin', 14.5412, 120.9588, 'Barangay 700', 'Malate');
select ok(
  (select category is null from public.crowd_report where description = 'Baha na naman dito sa amin'),
  'with no active model a report is stored untagged, not refused');
update public.classifier_model set is_active = true where model_id = 'v1-sample';

-- ------------------------------------------------ NDRRMC reports (A5, A6)

select ok(
  not has_function_privilege('anon', 'public.report_source(timestamptz, timestamptz)', 'execute')
  and not has_function_privilege('anon',
        'public.save_ndrrmc_report(text, timestamptz, timestamptz, text, jsonb, int)', 'execute')
  and not has_function_privilege('anon', 'public.finalize_ndrrmc_report(text)', 'execute'),
  'anon cannot read report figures or save reports');

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select throws_ok(
  $$ select public.report_source(now() - interval '1 day', now() + interval '1 minute') $$,
  'P0001', 'not_allowed', 'a dispatcher cannot read report figures (admins only)');
select throws_ok(
  $$ select public.save_ndrrmc_report(null, now() - interval '1 day', now() + interval '1 minute', 'Report',
       '[{"key": "overview", "title": "Situation overview", "body": "Text."}]'::jsonb) $$,
  'P0001', 'not_allowed', 'a dispatcher cannot save a report');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select ok(
  (select (s ->> 'incidents')::int = (select count(*)::int from public.incident_report
                                       where received_at >= now() - interval '1 day'
                                         and received_at < now() + interval '1 minute')
      and (s ->> 'incidents')::int = (s ->> 'resolved')::int + (s ->> 'open')::int + (s ->> 'false_reports')::int
      and (s ->> 'incidents')::int = (s ->> 'sos')::int + (s ->> 'clusters')::int
      and (select sum((t ->> 'count')::int) from jsonb_array_elements(s -> 'by_type') t) = (s ->> 'incidents')::int
      and (select sum((b ->> 'count')::int) from jsonb_array_elements(s -> 'by_barangay') b) = (s ->> 'incidents')::int
     from (select public.report_source(now() - interval '1 day', now() + interval '1 minute') s) x),
  'the figures cover every incident of the period and add up');
select ok(
  (select (s ->> 'completion_reports')::int = 1 and (s ->> 'persons_assisted')::int = 1
      and s -> 'outcomes' ->> 'transported' = '1' and (s ->> 'dispatches')::int >= 2
      and (s ->> 'alerts_issued')::int > 0 and (s ->> 'max_signal')::int = 4
     from (select public.report_source(now() - interval '1 day', now() + interval '1 minute') s) x),
  'they count what responders reported, the dispatches, the alerts, and the highest readings');
select ok(
  (select s::text !~* '(dela cruz|maria|ramos|fullname|latitude|longitude|contact|address)'
     from (select public.report_source(now() - interval '30 days', now() + interval '1 minute') s) x),
  'the figures hold no names, contact details, addresses, or coordinates (RA 10173)');
select throws_ok($$ select public.report_source(now(), now() - interval '1 day') $$,
  'P0001', 'invalid_value', 'a period that ends before it starts is refused');

select ok(
  public.save_ndrrmc_report(null, now() - interval '1 day', now() + interval '1 minute', ' Flood report ',
    '[{"key": "overview", "title": "Situation overview", "body": "Text."}]'::jsonb, 4200) like 'RPT-%',
  'an admin saves a draft');
select ok(
  (select status = 'draft' and title = 'Flood report' and method = 'assembled'
          and created_by_name = 'Test Admin' and generation_ms = 4200
          and (source ->> 'completion_reports')::int = 1
          and period_end > period_start
     from public.ndrrmc_report where title = 'Flood report'),
  'the draft keeps the period''s figures and who made it');
select throws_ok(
  $$ select public.save_ndrrmc_report(null, now() - interval '1 day', now(), 'Empty', '[]'::jsonb) $$,
  'P0001', 'invalid_value', 'a report needs at least one section');
select throws_ok(
  $$ select public.save_ndrrmc_report(null, now() - interval '1 day', now(), '  ',
       '[{"key": "overview", "title": "Situation overview", "body": "Text."}]'::jsonb) $$,
  'P0001', 'invalid_value', 'a report needs a title');
select lives_ok(
  $$ select public.save_ndrrmc_report(
       (select report_id from public.ndrrmc_report where title = 'Flood report'),
       now() - interval '9 days', now(), 'Flood report, revised',
       '[{"key": "overview", "title": "Situation overview", "body": "Edited."},
         {"key": "remarks", "title": "Remarks and recommendations", "body": ""}]'::jsonb) $$,
  'an admin edits the draft');
select ok(
  (select jsonb_array_length(sections) = 2 and sections -> 0 ->> 'body' = 'Edited.'
          and (source ->> 'completion_reports')::int = 1
          and period_start > now() - interval '2 days'
     from public.ndrrmc_report where title = 'Flood report, revised'),
  'editing changes the text, not the period or its figures');
select throws_ok(
  $$ select public.save_ndrrmc_report('RPT-9999', now() - interval '1 day', now(), 'Report',
       '[{"key": "overview", "title": "Situation overview", "body": "Text."}]'::jsonb) $$,
  'P0001', 'not_found', 'an unknown report cannot be edited');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select is((select count(*)::int from public.ndrrmc_report), 0,
  'a dispatcher cannot read reports');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select lives_ok(
  $$ select public.finalize_ndrrmc_report(
       (select report_id from public.ndrrmc_report where title = 'Flood report, revised')) $$,
  'an admin marks the report final');
select ok(
  (select status = 'final' and finalized_at is not null and finalized_by_name = 'Test Admin'
     from public.ndrrmc_report where title = 'Flood report, revised'),
  'it records when and by whom');
select throws_ok(
  $$ select public.finalize_ndrrmc_report(
       (select report_id from public.ndrrmc_report where title = 'Flood report, revised')) $$,
  'P0001', 'already_final', 'a final report cannot be made final again');
select throws_ok(
  $$ select public.save_ndrrmc_report(
       (select report_id from public.ndrrmc_report where title = 'Flood report, revised'),
       now() - interval '1 day', now(), 'Changed',
       '[{"key": "overview", "title": "Situation overview", "body": "Changed."}]'::jsonb) $$,
  'P0001', 'already_final', 'a final report cannot be edited');
select is(
  (select string_agg(action_type || ' ' || detail, '; ' order by log_id) from public.audit_log
    where action_type in ('reportDrafted', 'reportFinalized')),
  'reportDrafted Flood report; reportFinalized Flood report, revised',
  'drafting and finalizing are in the audit log (FR11)');

-- ------------------------------------------------ rescue confirmations (FR6)

reset role;
select ok(
  not has_function_privilege('authenticated', 'public.claim_rescue_confirmations()', 'execute')
  and not has_function_privilege('authenticated',
        'public.finish_rescue_confirmation(bigint, text, text)', 'execute')
  and not has_function_privilege('anon', 'public.mark_rescue_confirmation_read(bigint)', 'execute')
  and has_function_privilege('service_role', 'public.claim_rescue_confirmations()', 'execute'),
  'only the sender (service role) can claim rescue texts or record their outcome');

-- Earlier in this test a dispatcher assigned R-03 to res-001's SOS
-- (INC-0147), and R-05 arrived at res-003's (INC-0142) and closed it.
select is(
  (select string_agg(c.kind || ':' || c.unit_call_sign || ':' || c.sms_status, ','
            order by c.confirmation_id)
     from public.rescue_confirmation c
     join public.incident_report i on i.incident_id = c.incident_id
    where i.incident_id = 'INC-0147'),
  'assigned:R-03:queued',
  'assigning a unit to an SOS tells its resident, with one text waiting to go');
select is(
  (select string_agg(c.kind || ':' || c.unit_call_sign || ':' || c.sms_status, ','
            order by c.confirmation_id)
     from public.rescue_confirmation c
     join public.incident_report i on i.incident_id = c.incident_id
    where i.incident_id = 'INC-0142'),
  'onScene:R-05:none,resolved:R-05:none',
  'arrival and closing are told in the app only');
select is(
  (select count(*)::int from public.rescue_confirmation c
     join public.incident_report i on i.incident_id = c.incident_id
    where i.origin <> 'sos'),
  0, 'a crowd-report cluster has no single resident to tell');
select set_config('test.other_confirmation',
  (select confirmation_id::text from public.rescue_confirmation
    where incident_id = 'INC-0142' and kind = 'onScene'), true);

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is(
  (select string_agg(incident_id || ':' || kind, ',') from public.rescue_confirmation),
  'INC-0147:assigned', 'a resident reads the confirmations of their own SOS only');
select lives_ok(
  $$ select public.mark_rescue_confirmation_read(
       (select confirmation_id from public.rescue_confirmation where incident_id = 'INC-0147')) $$,
  'a resident marks theirs as read');
select lives_ok(
  $$ select public.mark_rescue_confirmation_read(current_setting('test.other_confirmation')::bigint) $$,
  'marking someone else''s is accepted and changes nothing');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000f", "role": "authenticated"}';
select is((select count(*)::int from public.rescue_confirmation), 0,
  'another resident reads none of them');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}';
select is((select count(*)::int from public.rescue_confirmation), 0,
  'a responder reads none of them');
select throws_ok($$ select public.mark_rescue_confirmation_read(1) $$,
  'P0001', 'not_allowed', 'only a resident marks a confirmation read');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select is((select count(*)::int from public.rescue_confirmation), 3,
  'a dispatcher sees what each resident was told');

reset role;
select ok(
  (select read_at is not null from public.rescue_confirmation where incident_id = 'INC-0147')
  and (select read_at is null from public.rescue_confirmation
        where confirmation_id = current_setting('test.other_confirmation')::bigint),
  'only the resident''s own confirmation is marked read');

create temp table __rescue as select public.claim_rescue_confirmations() as claimed;
select ok(
  (select jsonb_array_length(claimed) = 1
      and claimed -> 0 ->> 'incident_id' = 'INC-0147'
      and claimed -> 0 ->> 'kind' = 'assigned'
      and claimed -> 0 ->> 'unit_call_sign' = 'R-03'
      and claimed -> 0 ->> 'to' = (select contact_number from public.manila_resident
                                    where manila_resident_id = 'res-001')
     from __rescue),
  'the sender claims the waiting text with the unit and the resident''s number');
select is(jsonb_array_length(public.claim_rescue_confirmations()), 0,
  'a second run claims nothing, so nothing is texted twice');
select throws_ok(
  $$ select public.finish_rescue_confirmation(
       (select confirmation_id from public.rescue_confirmation where incident_id = 'INC-0147'),
       'queued') $$,
  'P0001', 'invalid_value', 'only a final outcome can be recorded for a rescue text');
select lives_ok(
  $$ select public.finish_rescue_confirmation(
       (select confirmation_id from public.rescue_confirmation where incident_id = 'INC-0147'),
       'sent') $$,
  'the sender records the outcome of a rescue text');
select throws_ok(
  $$ select public.finish_rescue_confirmation(
       (select confirmation_id from public.rescue_confirmation where incident_id = 'INC-0147'),
       'sent') $$,
  'P0001', 'not_found', 'the outcome of a rescue text is recorded once');

-- Simulation mode: told in the app, never texted. A reassignment tells the
-- resident again without a second text.
update public.app_setting set value = 'true' where key = 'demo.simulation';
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select public.assign_unit('INC-0149', 'unit-r07');
select public.assign_unit('INC-0147', 'unit-r05');
select is(
  (select string_agg(c.kind || ':' || c.unit_call_sign || ':' || c.sms_status, ','
            order by c.confirmation_id)
     from public.rescue_confirmation c
     join public.incident_report i on i.incident_id = c.incident_id
    where i.incident_id = 'INC-0149'),
  'assigned:R-07:simulated', 'in simulation mode the rescue text is simulated, never sent');
select is(
  (select string_agg(c.kind || ':' || c.unit_call_sign || ':' || c.sms_status, ','
            order by c.confirmation_id)
     from public.rescue_confirmation c
     join public.incident_report i on i.incident_id = c.incident_id
    where i.incident_id = 'INC-0147'),
  'assigned:R-03:sent,assigned:R-05:none',
  'a reassignment tells the resident again in the app, without a second text');

-- An SOS texted from an unknown SIM gets a unit before the app's copy
-- names the resident; the SMS channel is off.
reset role;
update public.app_setting set value = 'false' where key = 'demo.simulation';
update public.app_setting set value = 'false' where key = 'channels.sms';
select public.intake_sms_sos('09995550001', '00000000-0000-4000-8000-0000000005b3', now(), 14.6001, 120.9801, 15, false);
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select public.assign_unit(
  (select incident_id from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000005b3'),
  'unit-r09');
select is(
  (select count(*)::int from public.rescue_confirmation c
     join public.incident_report i on i.incident_id = c.incident_id
    where i.client_uuid = '00000000-0000-4000-8000-0000000005b3'),
  0, 'an SOS with no known resident has nobody to tell yet');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select public.submit_sos('00000000-0000-4000-8000-0000000005b3', now(), 14.6001, 120.9801, 15, null, null, false);
reset role;
select is(
  (select string_agg(c.kind || ':' || c.unit_call_sign || ':' || c.sms_status, ','
            order by c.confirmation_id)
     from public.rescue_confirmation c
     join public.incident_report i on i.incident_id = c.incident_id
    where i.client_uuid = '00000000-0000-4000-8000-0000000005b3'),
  'assigned:R-09:off',
  'once the SOS has its resident they are told a unit is coming; a switched-off SMS channel is logged as off');

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select public.mark_false_report(
  (select incident_id from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000005b3'),
  'Prank');
select public.resolve_incident('INC-0149');
select is(
  (select count(*)::int from public.rescue_confirmation c
     join public.incident_report i on i.incident_id = c.incident_id
    where i.client_uuid = '00000000-0000-4000-8000-0000000005b3' and c.kind = 'resolved'),
  0, 'a false report sends no closing confirmation');
select is(
  (select string_agg(c.kind || ':' || c.unit_call_sign || ':' || c.sms_status, ','
            order by c.confirmation_id)
     from public.rescue_confirmation c
     join public.incident_report i on i.incident_id = c.incident_id
    where i.incident_id = 'INC-0149'),
  'assigned:R-07:simulated,resolved:R-07:none', 'closing an SOS tells its resident');

-- A text that waited too long is no longer news.
reset role;
insert into public.rescue_confirmation
  (incident_id, manila_resident_id, kind, unit_call_sign, sms_status, created_at)
values ('INC-0147', 'res-001', 'assigned', 'R-03', 'queued', now() - interval '31 minutes');
select is(jsonb_array_length(public.claim_rescue_confirmations()), 0,
  'a rescue text that waited over 30 minutes is not claimed');
select is(
  (select sms_status from public.rescue_confirmation
    where created_at < now() - interval '30 minutes'),
  'expired', 'it is logged as expired');

reset role;
select * from finish();
rollback;
