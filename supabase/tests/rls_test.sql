-- Row Level Security and privilege checks (CLAUDE.md: no table ships without
-- RLS policies and a test). Run with `supabase test db` (pgTAP).
--
-- Everything runs in one transaction that is rolled back: it loads fresh demo
-- data and creates a throwaway account for each role, then acts as each one.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(556);

-- reset_demo_data() sets the record-number counters back, and a counter is
-- not undone by the rollback: on the hosted project that made the next real
-- SOS reuse an incident number (2026-10-19). Remember them here; they are
-- put back at the end.
create temp table __counters as
  select 'public.incident_number_seq'::regclass as seq, last_value from public.incident_number_seq
  union all select 'public.crowd_report_number_seq'::regclass, last_value from public.crowd_report_number_seq
  union all select 'public.resident_number_seq'::regclass, last_value from public.resident_number_seq;

select public.reset_demo_data();
-- What the checks below assume, whatever the database is set to or holds
-- (the hosted project has no sample classifier, and its switches are
-- MDRRMD's to change).
select public.load_sample_classifier();
update public.app_setting set value = 'false'
 where key in ('channels.facebook', 'channels.facebook_incidents');
update public.app_setting set value = 'true' where key in ('channels.push', 'channels.sms');

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
select ok(not has_function_privilege('anon', 'public.sos_delivery_report(timestamptz, timestamptz)', 'execute'),
  'anon cannot read the SOS delivery report');
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
select throws_ok($$ select public.sos_delivery_report(now() - interval '1 day', now()) $$,
  'P0001', 'not_allowed', 'a dispatcher cannot read the SOS delivery report (admins only)');
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
-- Objective 3: the four demo SOS (two by app, two by SMS), each counted
-- once on its first tier, all received seconds after capture.
select results_eq(
  $$ select sum((c->>'count')::int)::int, sum((c->>'within_900')::int)::int,
            string_agg(c->>'channel', ',' order by c->>'channel')
       from jsonb_array_elements(public.sos_delivery_report(
              now() - interval '1 day', now() + interval '1 minute') -> 'channels') c $$,
  $$ values (4, 4, 'app,sms') $$,
  'SOS delivery: one row per first tier, delays from capture to receipt');
select throws_ok($$ select public.sos_delivery_report(now(), now() - interval '1 day') $$,
  'P0001', 'invalid_value', 'the SOS delivery report refuses a period that ends before it starts');
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
  (select barangay from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000005b1'),
  (select name from private.barangay_at(14.6090, 120.9920)),
  'an SMS SOS names the barangay where the text says the phone is, not the home one');
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
select ok(
  not has_function_privilege('anon', 'public.simulate_sos(text, boolean)', 'execute')
  and not has_function_privilege('anon', 'public.simulate_crowd_reports(text, text, int)', 'execute'),
  'anon cannot simulate incidents');

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
select throws_ok($$ select public.simulate_sos('Barangay 700') $$,
  'P0001', 'not_allowed', 'a dispatcher cannot simulate incidents');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select throws_ok($$ select public.simulate_weather(3, 35, 2.5) $$,
  'P0001', 'not_allowed', 'simulated weather needs simulation mode');
select throws_ok($$ select public.simulate_crowd_reports('Barangay 700', 'fire', 3) $$,
  'P0001', 'not_allowed', 'simulated incidents need simulation mode');
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

-- Simulated incidents (migration simulated_incidents). Barangay 700 has no
-- demo reports nearby, so DBSCAN sees only the three simulated ones.
select throws_ok($$ select public.simulate_sos('Nowhere') $$,
  'P0001', 'invalid_value', 'a simulated SOS needs a real barangay');
select throws_ok($$ select public.simulate_crowd_reports('Barangay 700', 'fire', 6) $$,
  'P0001', 'invalid_value', 'at most five simulated reports at a time');
select lives_ok($$ select public.simulate_sos('Barangay 700', true) $$,
  'an admin simulates an SOS with a senior citizen');
select lives_ok($$ select public.simulate_crowd_reports('Barangay 700', 'fire', 3) $$,
  'an admin simulates three crowd reports');
select is(
  (select string_agg(origin || ':' || cardinality(crowd_report_ids) || ':' || array_to_string(vulnerable, '+'), ',' order by origin)
     from public.incident_board where is_simulated and barangay = 'Barangay 700'),
  'crowdCluster:3:,sos:0:seniorCitizen',
  'both reach the board marked simulated; the three reports became one DBSCAN cluster');
select is(
  (select sum((c->>'count')::int)::int
     from jsonb_array_elements(public.sos_delivery_report(
            now() - interval '1 day', now() + interval '1 minute') -> 'channels') c),
  (select count(*)::int from public.incident_board
    where origin = 'sos' and not is_simulated and received_at >= now() - interval '1 day'),
  'the Objective 3 report leaves the simulated SOS out');
select ok(
  (select count(*) = 2 from public.audit_log
    where account_name = 'Test Admin' and action_type in ('sosSimulated', 'reportsSimulated')),
  'both are in the audit log (FR11)');

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
  '{"hotline": "(02) 8527-0000", "sms_gateway": "+639175550199", "min_build": 1}'::jsonb,
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
  and not has_function_privilege('authenticated', 'private.classify_report(text)', 'execute')
  and not has_function_privilege('authenticated', 'public.load_sample_classifier()', 'execute')
  and not has_function_privilege('anon', 'public.load_sample_classifier()', 'execute'),
  'anon cannot read the model; clients cannot call the classifier directly or load the sample model');

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
                                         and received_at < now() + interval '1 minute'
                                         and not is_simulated)
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

-- Its PDF is kept in the private bucket (migration report_pdfs).
select ok(not has_function_privilege('anon', 'public.attach_report_pdf(text)', 'execute'),
  'anon cannot record a stored PDF');
select throws_ok(
  $$ select public.attach_report_pdf(
       (select report_id from public.ndrrmc_report where title = 'Flood report, revised')) $$,
  'P0001', 'not_found', 'a PDF is recorded only once its file is in the bucket');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name)
     select 'ndrrmc-reports', report_id || '-copy.pdf' from public.ndrrmc_report
      where title = 'Flood report, revised' $$,
  '42501', null, 'the bucket takes only a final report''s own file name');
select lives_ok(
  $$ insert into storage.objects (bucket_id, name)
     select 'ndrrmc-reports', report_id || '.pdf' from public.ndrrmc_report
      where title = 'Flood report, revised' $$,
  'an admin stores the final report''s PDF');
select ok(
  public.attach_report_pdf(
    (select report_id from public.ndrrmc_report where title = 'Flood report, revised')) is not null,
  'and records it on the report');
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

-- ------------------------------------------------ push notifications (FR6, FR14)

reset role;
select ok(
  not has_function_privilege('anon', 'public.register_push_device(text)', 'execute')
  and not has_function_privilege('anon', 'public.forget_push_device(text)', 'execute')
  and not has_function_privilege('authenticated', 'public.claim_push_messages()', 'execute')
  and not has_function_privilege('authenticated',
        'public.finish_push_message(bigint, text, int, int, text)', 'execute')
  and not has_function_privilege('authenticated', 'public.forget_push_tokens(text[])', 'execute')
  and has_function_privilege('service_role', 'public.claim_push_messages()', 'execute'),
  'only the sender (service role) can claim pushes, record outcomes, or drop tokens');
select ok(
  not has_table_privilege('authenticated', 'public.push_device', 'select')
  and not has_table_privilege('authenticated', 'public.push_message', 'select')
  and not has_table_privilege('anon', 'public.push_device', 'select'),
  'no client can read the phones'' tokens or the push queue');

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select lives_ok($$ select public.register_push_device('fcm-token-resident-phone-0001') $$,
  'a signed-in resident registers their phone for push');
select lives_ok($$ select public.register_push_device(' fcm-token-resident-phone-0001 ') $$,
  'registering the same phone again is accepted');
select throws_ok($$ select public.register_push_device('short') $$,
  'P0001', 'invalid_value', 'a token that cannot be real is refused');
select throws_ok($$ select count(*) from public.push_device $$,
  '42501', null, 'a resident cannot read the token table');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-000000000011", "role": "authenticated"}';
select lives_ok($$ select public.register_push_device('fcm-token-responder-phone-0002') $$,
  'a responder registers their phone');
select lives_ok($$ select public.forget_push_device('fcm-token-resident-phone-0001') $$,
  'forgetting another account''s token is accepted and changes nothing');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000e", "role": "authenticated"}';
select public.register_push_device('fcm-token-stranger-phone-' || g) from generate_series(1, 6) g;

reset role;
select is(
  (select string_agg(user_id::text || ' ' || token, ', ' order by token) from public.push_device
    -- Only this test's phones: the database may hold real ones.
    where token like 'fcm-token-%' and token not like 'fcm-token-stranger-%' and forgotten_at is null),
  '00000000-0000-4000-8000-00000000000c fcm-token-resident-phone-0001, 00000000-0000-4000-8000-000000000011 fcm-token-responder-phone-0002',
  'one row per phone, with whitespace trimmed; forgetting another account''s token did nothing');
select is((select count(*)::int from public.push_device where user_id = '00000000-0000-4000-8000-00000000000e'), 6,
  'every phone an account signs in on is kept');

-- A unit with a responder is sent to the resident's SOS.
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select public.set_responder_unit('00000000-0000-4000-8000-000000000011', 'unit-r20');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select public.assign_unit(
  (select incident_id from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000005a1'), 'unit-r20');
reset role;
select ok(
  (select m.kind = 'assignment' and m.status = 'queued'
          and m.title = 'New assignment: ' || i.incident_id
          and m.body = 'Flood · Barangay 412, Sampaloc. Open S.A.G.I.P. to accept.'
          and m.data = jsonb_build_object('type', 'assignment', 'incident_id', i.incident_id)
     from public.push_message m, public.incident_report i
    where m.user_id = '00000000-0000-4000-8000-000000000011' and i.client_uuid = '00000000-0000-4000-8000-0000000005a1'
    order by m.message_id desc limit 1),
  'a new assignment queues a push to the responders on that unit');
select ok(
  (select m.kind = 'rescue' and m.status = 'queued'
          and m.title = 'A rescue team is coming'
          and m.body = 'R-20 has been sent to your location. Stay where you are if it is safe.'
          and m.data ->> 'type' = 'rescue'
          and m.data ->> 'incident_id' = i.incident_id
     from public.push_message m, public.incident_report i
    where m.user_id = '00000000-0000-4000-8000-00000000000c' and i.client_uuid = '00000000-0000-4000-8000-0000000005a1'
    order by m.message_id desc limit 1),
  'the rescue confirmation queues a push to the resident''s phones (FR6)');
select is(
  (select count(*)::int from public.push_message m
     join public.rescue_confirmation c on c.confirmation_id = (m.data ->> 'confirmation_id')::bigint
    where m.kind = 'rescue' and c.manila_resident_id <> 'res-001' and c.manila_resident_id <> 'res-002'),
  0, 'a resident with no account (res-003) gets no push');

-- A push that waited too long, and one for the account with six phones.
insert into public.push_message (user_id, kind, title, body, created_at)
values ('00000000-0000-4000-8000-00000000000c', 'rescue', 'Old', 'Old', now() - interval '31 minutes'),
       ('00000000-0000-4000-8000-00000000000e', 'rescue', 'Six phones', 'Six phones', now());

create temp table __push as select public.claim_push_messages() as claimed;
select ok(
  (select bool_and(jsonb_array_length(c -> 'tokens') >= 1) from __push, jsonb_array_elements(claimed) c)
  and (select count(*) = 1 from __push, jsonb_array_elements(claimed) c
        where c ->> 'kind' = 'assignment'
          and c -> 'tokens' = '["fcm-token-responder-phone-0002"]'::jsonb),
  'the sender claims each push with its account''s phones');
select is(
  (select jsonb_array_length(c -> 'tokens') from __push, jsonb_array_elements(claimed) c
    where c ->> 'title' = 'Six phones'),
  5, 'a push goes to the account''s five most recent phones at most');
select is(
  (select string_agg(distinct status, ',') from public.push_message where user_id = '00000000-0000-4000-8000-00000000000f'),
  'noDevice', 'a push for an account with no phone is closed as noDevice');
select is((select status from public.push_message where title = 'Old'), 'expired',
  'a push still waiting after 30 minutes is not sent');
select is((select count(*)::int from public.push_message where status = 'queued'), 0,
  'claimed pushes are marked as being sent');
select is(jsonb_array_length(public.claim_push_messages()), 0,
  'a second run claims nothing, so nothing is pushed twice');
select lives_ok(
  $$ select public.finish_push_message(
       (select message_id from public.push_message where user_id = '00000000-0000-4000-8000-000000000011' order by message_id desc limit 1),
       'sent', 1, 1) $$,
  'the sender records the outcome of a push');
select throws_ok(
  $$ select public.finish_push_message(
       (select message_id from public.push_message where user_id = '00000000-0000-4000-8000-000000000011' order by message_id desc limit 1),
       'sent', 1, 1) $$,
  'P0001', 'not_found', 'the outcome of a push is recorded once');
select throws_ok(
  $$ select public.finish_push_message(
       (select message_id from public.push_message where user_id = '00000000-0000-4000-8000-00000000000c' and status = 'sending' limit 1),
       'queued') $$,
  'P0001', 'invalid_value', 'only a final outcome can be recorded for a push');
select is(public.forget_push_tokens(array['fcm-token-responder-phone-0002', 'no-such-token']), 1,
  'tokens FCM no longer knows are marked forgotten');
select is(jsonb_array_length(private.push_tokens('00000000-0000-4000-8000-000000000011')), 0,
  'and get no more pushes');

-- With push switched off on A3, a new push is logged as off.
update public.app_setting set value = 'false' where key = 'channels.push';
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select public.resolve_incident(
  (select incident_id from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000005a1'));
reset role;
select is(
  (select status || ':' || title from public.push_message where user_id = '00000000-0000-4000-8000-00000000000c'
    order by message_id desc limit 1),
  'off:Your SOS was closed', 'with push switched off, the closing push is logged as off');

-- ------------------------------------------------ waking the sender

reset role;
select ok(
  not has_function_privilege('anon', 'public.sender_secret()', 'execute')
  and not has_function_privilege('authenticated', 'public.sender_secret()', 'execute')
  and has_function_privilege('service_role', 'public.sender_secret()', 'execute'),
  'only the sender (service role) can read the shared secret');
select is(length(public.sender_secret()), 64, 'the shared secret is made at random in the vault');
create temp table __wake as select (select count(*) from net.http_request_queue) as before;
insert into public.push_message (user_id, kind, title, body, status)
values ('00000000-0000-4000-8000-00000000000c', 'rescue', 'Not queued', 'Not queued', 'off');
select is((select count(*) from net.http_request_queue) - (select before from __wake), 0::bigint,
  'nothing queued: the sender is not called');
insert into public.push_message (user_id, kind, title, body)
values ('00000000-0000-4000-8000-00000000000c', 'rescue', 'Queued', 'Queued');
select is((select count(*) from net.http_request_queue) - (select before from __wake), 1::bigint,
  'something queued: the sender is called once, after the transaction commits');
select ok(
  (select url = 'https://imssgenjfirpohkwxwbv.supabase.co/functions/v1/send-alerts'
          and headers ->> 'x-sagip-key' = public.sender_secret()
     from net.http_request_queue order by id desc limit 1),
  'at its address, with the shared secret');

-- ------------------------------------------------ what the resident was told (D4)

reset role;
select ok(
  not has_function_privilege('anon', 'public.incident_notices(text)', 'execute'),
  'anon cannot read what a resident was told');
-- What the drawer should show, read straight from both tables.
create temp table __told as
  select c.incident_id,
         string_agg(c.kind || ':' || coalesce(c.unit_call_sign, '-') || ':' || c.sms_status || ':'
                    || coalesce((select m.status from public.push_message m
                                  where m.kind = 'rescue' and m.data ->> 'confirmation_id' = c.confirmation_id::text
                                  order by m.message_id desc limit 1), 'noApp'),
                    ',' order by c.created_at, c.confirmation_id) as told
    from public.rescue_confirmation c group by c.incident_id;
grant select on __told to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select throws_ok($$ select * from public.incident_notices('INC-0147') $$,
  'P0001', 'not_allowed', 'a resident cannot read the notices on the dashboard drawer');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}';
select throws_ok($$ select * from public.incident_notices('INC-0142') $$,
  'P0001', 'not_allowed', 'a responder cannot either');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select is(
  (select string_agg(n.kind || ':' || coalesce(n.unit_call_sign, '-') || ':' || n.sms_status || ':'
                     || coalesce(n.push_status, 'noApp'), ',')
     from public.incident_notices(
       (select incident_id from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000005a1')) n),
  -- SMS was switched off in the rescue section above, so the text is "off".
  'assigned:R-20:off:sending,resolved:R-20:none:off',
  'a dispatcher sees each notice with its text and push outcome, oldest first');
select is(
  (select string_agg(coalesce(n.push_status, 'noApp'), ',') from public.incident_notices('INC-0142') n),
  (select regexp_replace(told, '[^,]*:', '', 'g') from __told where incident_id = 'INC-0142'),
  'a resident with no app account shows no push');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select is(
  (select count(*)::int from __told t
    where t.told is distinct from (
      select string_agg(n.kind || ':' || coalesce(n.unit_call_sign, '-') || ':' || n.sms_status || ':'
                        || coalesce(n.push_status, 'noApp'), ',')
        from public.incident_notices(t.incident_id) n)),
  0, 'an admin sees the same as the tables hold, for every incident');

-- ------------------------------------------------ all 897 barangays (FR15)

reset role;
select ok(
  not has_function_privilege('anon', 'private.load_barangays(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'private.load_barangays(jsonb)', 'execute')
  and has_function_privilege('service_role', 'private.load_barangays(jsonb)', 'execute'),
  'only the SQL editor and the service role can load barangays');
select ok(
  not has_table_privilege('anon', 'public.manila_outline', 'select')
  and not has_table_privilege('authenticated', 'public.manila_outline', 'insert'),
  'anon cannot read the city outline and no client can change it');
select throws_ok($$ select private.load_barangays('{"barangays": []}') $$,
  'P0001', 'invalid_value', 'an empty barangay list is refused');
create temp table __brgy as select count(*)::int as before from public.barangay;
select is(
  private.load_barangays($j${
    "source": "RLS test squares",
    "barangays": [
      {"name": "Barangay 412", "district": "Sampaloc", "psgc": "1380606018",
       "polygons": [["wjbxAgtmaV?oKoK??nK"]], "center": [14.6, 120.99]},
      {"name": "Barangay Test", "district": "Sampaloc", "psgc": "1380699999",
       "polygons": [["wjbxAgmnaV?oKoK??nK"]], "center": [14.6, 120.994]}],
    "other": [{"name": "Not a barangay", "district": "Tondo", "polygons": [["kihxA{xkaV?gEgE??fE"]]}]
  }$j$::jsonb),
  2, 'loading writes each barangay in the file');
select is((select count(*)::int from public.barangay) - (select before from __brgy), 1,
  'a barangay already there is updated, not added again; a new one is added');
select ok(
  (select psgc_code = '1380606018' and center_latitude = 14.6 and center_longitude = 120.99
          and round(extensions.st_area(boundary)) between 45000 and 50000
     from public.barangay where name = 'Barangay 412'),
  'the existing barangay gets its code, center, and boundary (about 4.7 ha)');
select ok(
  private.inside_manila(14.6000, 120.9900) and private.inside_manila(14.6300, 120.9800),
  'inside a barangay, and inside an area in no barangay, is inside Manila');
select ok(private.inside_manila(14.6000, 120.9914),
  '43 m past the edge still counts (GPS error, simplified boundaries)');
select ok(not private.inside_manila(14.6000, 120.9920),
  'over 100 m from any part of the city is outside Manila');

-- ------------------------------------------------ the PAGASA feed (FR5)

reset role;
select ok(
  not has_function_privilege('authenticated', 'public.record_pagasa_reading(numeric, int, numeric)', 'execute')
  and not has_function_privilege('anon', 'public.record_pagasa_reading(numeric, int, numeric)', 'execute')
  and not has_function_privilege('authenticated', 'public.record_feed_status(text, boolean, text, jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'private.call_ingest_pagasa()', 'execute')
  and has_function_privilege('service_role', 'public.record_pagasa_reading(numeric, int, numeric)', 'execute'),
  'only the feed (service role) records PAGASA readings and feed status');
select is((select count(*)::int from cron.job where jobname = 'ingest-pagasa' and schedule = '*/10 * * * *'), 1,
  'the feed runs every 10 minutes');

update public.app_setting set value = 'true' where key = 'demo.simulation';
create temp table __feed as select (select count(*) from public.weather_alert) as rows_before;
select is(public.record_pagasa_reading(15, 2, 0), 'paused',
  'in simulation mode real readings are not recorded');
select is((select count(*) from public.weather_alert), (select rows_before from __feed),
  'and no reading was added');
update public.app_setting set value = 'false' where key = 'demo.simulation';
select is(public.record_pagasa_reading(15, 2, 0), 'recorded', 'a new reading is recorded');
select ok(
  (select rainfall_intensity = 15 and signal_level = 2 and storm_surge_m = 0 and not is_simulated
     from public.weather_alert order by issued_at desc, alert_id desc limit 1),
  'as a real (not simulated) row');
select is(public.record_pagasa_reading(15, 2, 0), 'unchanged', 'the same reading again adds nothing');
select is(public.record_pagasa_reading(null, 3, null), 'recorded', 'an unreadable source keeps its last value');
select ok(
  (select rainfall_intensity = 15 and signal_level = 3
     from public.weather_alert order by issued_at desc, alert_id desc limit 1),
  'rainfall stays 15 while the signal moves to 3');

select public.record_feed_status('pagasa_cyclone', true, null, '{"number": 18}');
select public.record_feed_status('pagasa_cyclone', false, 'HTTP 503', null);
select ok(
  (select not ok and failures = 1 and last_error = 'HTTP 503' and last_success_at is not null
          and seen = '{"number": 18}'::jsonb
     from public.feed_status where source = 'pagasa_cyclone'),
  'a failed check is counted and keeps the last good reading and time');

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is((select count(*)::int from public.feed_status), 0, 'residents cannot read the feed status');

-- ------------------------------------------------ tier 3: SOS relayed over Bluetooth
-- (Points inside the test squares the barangay section loaded above.)

reset role;
select ok(
  not has_function_privilege('anon', 'public.relay_sos(uuid, timestamptz, double precision, double precision, boolean, int)', 'execute')
  and has_function_privilege('authenticated', 'public.relay_sos(uuid, timestamptz, double precision, double precision, boolean, int)', 'execute')
  and not has_table_privilege('authenticated', 'public.sos_relay_log', 'select'),
  'any signed-in phone may relay an SOS; no app reads the relay log');

set local role authenticated;
-- A signed-in phone (no resident record, no staff role) heard an SOS.
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000e", "role": "authenticated"}';
select is(
  public.relay_sos('00000000-0000-4000-8000-0000000007a1', now() - interval '4 minutes', 14.6000, 120.9900, true, 2) ->> 'duplicate',
  'false', 'a relayed SOS is filed');
select is(
  public.relay_sos('00000000-0000-4000-8000-0000000007a1', now() - interval '4 minutes', 14.6000, 120.9900, true, 3) ->> 'duplicate',
  'true', 'the same SOS from another hop is one incident');
select throws_ok(
  $$ select public.relay_sos('00000000-0000-4000-8000-0000000007a2', now(), 14.5547, 121.0244, false, 1) $$,
  'P0001', 'outside_manila', 'a relayed SOS outside Manila is refused');
select throws_ok(
  $$ select public.relay_sos('00000000-0000-4000-8000-0000000007a3', now(), 14.6000, 120.9900, false, 7) $$,
  'P0001', 'invalid_value', 'a hop count the packet cannot hold is refused');

reset role;
select ok(
  (select channel = 'bleRelay' and status = 'pendingVerification' and not account_verified
          and manila_resident_id is null and mock_location
          and captured_at < received_at - interval '3 minutes'
     from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000007a1'),
  'on the board at once, unverified, from an unknown sender, with its capture time (FR8)');
select is(
  (select string_agg(hops || ':' || duplicate, ',' order by relay_id) from public.sos_relay_log
    where client_uuid = '00000000-0000-4000-8000-0000000007a1'),
  '2:false,3:true', 'every upload is logged with its hops');

-- The resident's own phone gets online and sends its copy.
create temp table __relayed as
  select incident_id from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000007a1';
grant select on __relayed to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is(
  public.submit_sos('00000000-0000-4000-8000-0000000007a1', now() - interval '4 minutes', 14.6000, 120.9900, 8),
  (select incident_id from __relayed),
  'the resident''s own copy finds the relayed incident');
reset role;
select ok(
  (select manila_resident_id = 'res-001' and account_verified
     from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000007a1'),
  'and attaches the resident');

insert into public.sos_relay_log (client_uuid, relayed_by, hops, duplicate)
select gen_random_uuid(), '00000000-0000-4000-8000-00000000000e', 1, false from generate_series(1, 30);
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000e", "role": "authenticated"}';
select throws_ok(
  $$ select public.relay_sos('00000000-0000-4000-8000-0000000007a4', now(), 14.6000, 120.9900, false, 1) $$,
  'P0001', 'rate_limited', 'a phone that uploads too many in an hour is stopped');

-- ------------------------------------------------ two-way SMS check (FR8)

reset role;
select ok(
  not has_function_privilege('authenticated', 'public.claim_sms_checks()', 'execute')
  and not has_function_privilege('authenticated', 'public.record_sms_check_reply(text, text)', 'execute')
  and not has_table_privilege('authenticated', 'public.sms_check', 'select'),
  'only the sender and sms-intake touch SMS checks (they hold full numbers)');
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select lives_ok($$ select public.send_sms_check((select incident_id from __relayed)) $$,
  'a dispatcher sends an SMS check');
reset role;
select is(
  (select count(*)::int from public.sms_check c join __relayed r using (incident_id)
    where private.phone_key(c.to_number) = private.phone_key('09170004821')),
  1, 'one text is queued to the resident''s number');
-- As the sender would after texting it.
update public.sms_check set status = 'sent', updated_at = now()
 where incident_id = (select incident_id from __relayed);
select ok(public.record_sms_check_reply('09170004821', 'Hello po') is null,
  'a text that is not YES or NO is no answer');
select is(public.record_sms_check_reply('+63 917 000 4821', 'Oo po, tulong') ->> 'answer', 'YES',
  'OO from that number is a YES');
select is(
  (select e.detail from public.incident_event e join __relayed r using (incident_id)
    where e.kind = 'smsReplyReceived' order by e.event_id desc limit 1),
  'YES', 'and it shows on the incident for the dispatcher');

-- ------------------------------------------------ PHIVOLCS earthquakes (FR14)

reset role;
select ok(
  not has_function_privilege('authenticated', 'public.record_phivolcs_events(jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.record_phivolcs_events(jsonb)', 'execute'),
  'only ingest-phivolcs records earthquakes');
select is(
  public.record_phivolcs_events('[
    {"key": "rls-1", "occurred_at": "2026-10-03T12:01:00+08:00", "latitude": 13.92, "longitude": 121.18,
     "depth_km": 23, "magnitude": 4.5, "location": "023 km S 66° E of Lobo (Batangas)", "distance_km": 123},
    {"key": "rls-2", "occurred_at": "2026-10-03T12:05:00+08:00", "latitude": 10.3, "longitude": 123.9,
     "depth_km": 10, "magnitude": 5.0, "location": "far away", "distance_km": 570}]'::jsonb),
  1, 'events within 300 km of Manila are kept; farther ones are not');
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is((select count(*)::int from public.phivolcs_event), 0, 'residents do not read the earthquake list');

-- ------------------------------------------------ river levels (FR5)

reset role;
select ok(
  not has_function_privilege('authenticated', 'public.record_river_levels(jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.record_river_levels(jsonb)', 'execute'),
  'only ingest-efcos records river levels');
select is(
  public.record_river_levels('[
    {"code": "rls-a", "name": "Fort Santiago", "latitude": 14.5953, "longitude": 120.9697,
     "observed_at": "2026-10-11T11:20:00+08:00", "level_m": 11.42, "change_m": -0.02,
     "alert_m": 12, "alarm_m": 12.5, "critical_m": 13, "flagged": true},
    {"code": "rls-b", "name": "Ugong", "latitude": 14.6863, "longitude": 121.0021,
     "observed_at": "2026-10-11T11:20:00+08:00", "level_m": 20.57, "change_m": null,
     "alert_m": 14.85, "alarm_m": 15.7, "critical_m": 16.6},
    {"code": "rls-c", "name": "Angono", "latitude": 14.5268, "longitude": 121.1424,
     "observed_at": "2026-10-11T11:20:00+08:00", "level_m": 12.04}]'::jsonb),
  3, 'each station''s reading is kept');
select is(
  (select string_agg(coalesce(state, 'none'), ',' order by station_code) from public.river_level
    where station_code like 'rls-%'),
  'normal,critical,none', 'each level is read against the station''s own levels');
select is(
  public.record_river_levels('[
    {"code": "rls-a", "name": "Fort Santiago", "latitude": 14.5953, "longitude": 120.9697,
     "observed_at": "2026-10-11T11:10:00+08:00", "level_m": 12.9, "alert_m": 12, "alarm_m": 12.5, "critical_m": 13}]'::jsonb),
  0, 'an older reading does not replace a newer one');
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is((select count(*)::int from public.river_level), 0, 'residents do not read river levels');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select is((select count(*)::int from public.river_level where station_code like 'rls-%'), 3,
  'dispatchers do');

-- ------------------------------------------------ Cancel SOS and the newest position

-- The resident's own SOS from the relay section (still open).
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000e", "role": "authenticated"}';
select throws_ok(
  $$ select public.request_sos_cancel('00000000-0000-4000-8000-0000000007a1', 'safeNow') $$,
  'P0001', 'not_allowed', 'only a resident asks to cancel');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select throws_ok(
  $$ select public.request_sos_cancel('00000000-0000-4000-8000-0000000007a1', 'bored') $$,
  'P0001', 'invalid_value', 'with one of the three reasons');
select throws_ok(
  $$ select public.request_sos_cancel('00000000-0000-4000-8000-0000000007ff', 'safeNow') $$,
  'P0001', 'not_found', 'and only their own SOS');
select lives_ok(
  $$ select public.request_sos_cancel('00000000-0000-4000-8000-0000000007a1', 'safeNow', ' All good ') $$,
  'a resident asks to cancel their SOS');
reset role;
select ok(
  (select status <> 'resolved' and cancel_requested_at is not null
          and cancel_reason = 'safeNow' and cancel_note = 'All good' and not cancelled
     from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000007a1'),
  'the SOS stays open, marked as asked');
select is(
  (select e.detail from public.incident_event e join __relayed r using (incident_id)
    where e.kind = 'cancelRequested'),
  'safeNow', 'and the timeline says so');
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select lives_ok(
  $$ select public.withdraw_sos_cancel('00000000-0000-4000-8000-0000000007a1') $$,
  'the resident takes it back');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select throws_ok(
  $$ select public.confirm_sos_cancel((select incident_id from __relayed)) $$,
  'P0001', 'invalid_value', 'a dispatcher cannot close as cancelled what nobody asked to cancel');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select ok(
  public.update_sos_location('00000000-0000-4000-8000-0000000007a1', 14.6001, 120.9901, 9),
  'the phone''s newest position is kept while the SOS is open');
select ok(
  not public.update_sos_location('00000000-0000-4000-8000-0000000007a1', 14.6002, 120.9902, 9),
  'but not more often than every 20 seconds');
select throws_ok(
  $$ select public.update_sos_location('00000000-0000-4000-8000-0000000007a1', 14.2, 121.5, 9) $$,
  'P0001', 'outside_manila', 'and not from outside Manila');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select ok(
  (select b.last_latitude = 14.6001 and b.latitude = 14.6000
     from public.incident_board b join __relayed r on r.incident_id = b.id),
  'the board shows it beside the place the SOS was sent from');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select lives_ok(
  $$ select public.request_sos_cancel('00000000-0000-4000-8000-0000000007a1', 'mistake') $$,
  'the resident asks again');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select lives_ok(
  $$ select public.confirm_sos_cancel((select incident_id from __relayed)) $$,
  'now a dispatcher closes it as cancelled');
reset role;
select ok(
  (select status = 'resolved' and cancelled and resolved_at is not null
     from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000007a1'),
  'the SOS is resolved, as cancelled');
select ok(
  exists (select 1 from public.audit_log a join __relayed r on r.incident_id = a.target_id
           where a.action_type = 'sosCancelled' and a.account_name = 'Test Dispatcher' and a.detail = 'mistake'),
  'and the close is audited');
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select throws_ok(
  $$ select public.update_sos_location('00000000-0000-4000-8000-0000000007a1', 14.6003, 120.9903, 9) $$,
  'P0001', 'incident_closed', 'a closed SOS takes no more positions');

-- ------------------------------------------------ data retention (A3, RA 10173)

reset role;
select ok(
  not has_function_privilege('authenticated', 'private.apply_retention()', 'execute')
  and not has_function_privilege('anon', 'private.apply_retention()', 'execute'),
  'only the nightly job applies retention');
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select throws_ok(
  $$ select public.set_setting('privacy.retention_months', '3'::jsonb) $$,
  'P0001', 'invalid_value', 'the period cannot go below six months');
reset role;
-- The cancelled SOS, as if it had been closed 13 months ago.
update public.incident_report
   set resolved_at = now() - interval '13 months', note = 'Second floor, blue gate', address = '1482 Dapitan St'
 where client_uuid = '00000000-0000-4000-8000-0000000007a1';
select ok(
  (private.apply_retention() ->> 'incidents')::int >= 1,
  'incidents closed for longer than the period are stripped');
select ok(
  (select manila_resident_id is null and note is null and address is null and cancel_note is null
          and last_latitude is null and anonymized_at is not null
          and latitude = round(latitude::numeric, 3)::double precision
          and barangay is not null and status = 'resolved'
     from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000007a1'),
  'the person and the exact place are gone; the record stays');
select is(
  (select count(*)::int from public.rescue_confirmation c join __relayed r using (incident_id)),
  0, 'what the resident was told goes with it');
select ok(
  not exists (select 1 from public.incident_report where status <> 'resolved' and anonymized_at is not null),
  'open incidents are never touched');
select ok(
  exists (select 1 from public.audit_log
           where action_type = 'retentionApplied' and account_role = 'system'),
  'and the run is audited as System');

-- ------------------------------------------------ NDRRMC report: the RAG step

select ok(
  not has_function_privilege('authenticated', 'public.finish_report_rewrite(bigint, boolean, text, int, text)', 'execute')
  and not has_function_privilege('authenticated', 'public.record_reference_embedding(bigint, text, jsonb)', 'execute'),
  'only generate-report finishes a rewrite or stores an embedding');
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select throws_ok(
  $$ select public.begin_report_rewrite() $$,
  'P0001', 'not_allowed', 'a dispatcher cannot ask the language model for a report');
select is((select count(*)::int from public.report_reference), 0,
  'and does not read the reference passages');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select ok(public.begin_report_rewrite() > 0, 'an admin can');
select ok((select count(*) >= 12 from public.report_reference), 'and reads the passages');
select lives_ok(
  $$ select public.mark_report_rag(public.save_ndrrmc_report(null, now() - interval '1 day', now() + interval '1 minute', 'RAG draft',
       '[{"key": "overview", "title": "Situation overview", "body": "Text."}]'::jsonb)) $$,
  'a rewritten draft is saved and marked');
select is(
  (select method from public.ndrrmc_report where title = 'RAG draft'), 'rag',
  'as written with the language model');
select throws_ok(
  $$ select public.mark_report_rag('RPT-9999') $$,
  'P0001', 'not_found', 'only a draft that exists');
reset role;
insert into public.report_rewrite (staff_id)
select '00000000-0000-4000-8000-00000000000a' from generate_series(1, 20);
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select throws_ok(
  $$ select public.begin_report_rewrite() $$,
  'P0001', 'rate_limited', 'at most 20 rewrites an hour for each admin');

-- ------------------------------------------------ unit inventory

reset role;
-- Wherever the checks above left them: the responder is on R-05, the
-- second responder is on no unit.
update public.staff set unit_id = 'unit-r05', deactivated_at = null
 where id = '00000000-0000-4000-8000-00000000000b';
update public.staff set unit_id = null, deactivated_at = null
 where id = '00000000-0000-4000-8000-000000000011';
select ok(
  not has_table_privilege('authenticated', 'public.unit_supply', 'insert')
  and not has_table_privilege('authenticated', 'public.unit_supply', 'update')
  and not has_table_privilege('authenticated', 'public.unit_supply', 'delete')
  and not has_table_privilege('anon', 'public.unit_supply', 'select')
  and not has_function_privilege('anon', 'public.set_unit_supply(text, numeric, numeric)', 'execute'),
  'unit supplies change only through set_unit_supply, and not for visitors');

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select throws_ok(
  $$ select public.set_unit_supply('fuel', 50) $$,
  'P0001', 'not_allowed', 'a dispatcher cannot report a unit''s supplies');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select throws_ok(
  $$ select public.set_unit_supply('fuel', 50) $$,
  'P0001', 'not_allowed', 'nor an admin');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select throws_ok(
  $$ select public.set_unit_supply('fuel', 50) $$,
  'P0001', 'not_allowed', 'nor a resident');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-000000000011", "role": "authenticated"}';
select throws_ok(
  $$ select public.set_unit_supply('fuel', 50) $$,
  'P0001', 'not_allowed', 'nor a responder who is on no unit');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}';
select lives_ok(
  $$ select public.set_unit_supply('fuel', 20) $$,
  'a responder reports their unit''s fuel as a percent');
select lives_ok(
  $$ select public.set_unit_supply('drinkingWater', 6, 24) $$,
  'and a stock as a count against a full load');
select lives_ok(
  $$ select public.set_unit_supply('drinkingWater', 5) $$,
  'and again without the full load');
select results_eq(
  $$ select item, quantity, capacity, updated_by_name from public.unit_supply order by item $$,
  $$ values ('drinkingWater'::text, 5::numeric, 24::numeric, 'Test Responder'::text),
            ('fuel', 20, 100, 'Test Responder') $$,
  'the full load is remembered, fuel is out of 100, and the crew reads its own unit''s supplies');
select throws_ok(
  $$ select public.set_unit_supply('fuel', 101) $$,
  'P0001', 'invalid_value', 'no more than full');
select throws_ok(
  $$ select public.set_unit_supply('medicalKits', 3) $$,
  'P0001', 'invalid_value', 'a stock''s first report needs its full load');
select throws_ok(
  $$ select public.set_unit_supply('lifeVests', 2.5, 5) $$,
  'P0001', 'invalid_value', 'stocks are whole numbers');
select throws_ok(
  $$ select public.set_unit_supply('rescueGear', 7, 5) $$,
  'P0001', 'invalid_value', 'no more on board than a full load');
select throws_ok(
  $$ select public.set_unit_supply('oxygen', 1, 2) $$,
  'P0001', 'invalid_value', 'only the listed supplies');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select is((select count(*)::int from public.unit_supply where unit_id = 'unit-r05'), 2,
  'a dispatcher reads every unit''s supplies');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-000000000011", "role": "authenticated"}';
select is((select count(*)::int from public.unit_supply), 0,
  'a responder on another or no unit does not');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is((select count(*)::int from public.unit_supply), 0, 'nor a resident');
reset role;
select is(
  (select detail from public.audit_log where action_type = 'supplyUpdated' order by log_id desc limit 1),
  'drinkingWater 5 of 24', 'each report is audited');
select is(
  (select count(*)::int from public.audit_log where action_type = 'supplyUpdated' and target_id = 'unit-r05'), 3,
  'and a refused one is not');

-- ------------------------------------------------ a unit's station position

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select throws_ok(
  $$ select public.set_unit_home('unit-r05', 14.6, 120.99) $$,
  'P0001', 'not_allowed', 'a dispatcher cannot set a unit''s station position');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select lives_ok(
  $$ select public.set_unit_home('unit-r05', 14.6, 120.99) $$,
  'an admin can');
select throws_ok(
  $$ select public.set_unit_home('unit-r05', 15.2, 121.0) $$,
  'P0001', 'invalid_value', 'only a place in or beside Manila');
select throws_ok(
  $$ select public.set_unit_home('unit-r05', 14.6, null) $$,
  'P0001', 'invalid_value', 'both numbers or neither');
select throws_ok(
  $$ select public.set_unit_home('unit-none', 14.6, 120.99) $$,
  'P0001', 'not_found', 'only a unit that exists');
reset role;
update public.response_unit
   set status = 'onScene', last_latitude = 14.61, last_longitude = 120.98, last_location_at = now()
 where unit_id = 'unit-r05';
update public.response_unit set status = 'available' where unit_id = 'unit-r05';
select results_eq(
  $$ select home_latitude, home_longitude, last_latitude, last_location_at is not null
       from public.response_unit where unit_id = 'unit-r05' $$,
  $$ values (14.6::double precision, 120.99::double precision, 14.61::double precision, true) $$,
  'the station is kept apart from the crew''s last fix, which a finished job leaves as it is');
select is(
  (select detail from public.audit_log where action_type = 'unitEdited' and target_id = 'unit-r05' order by log_id desc limit 1),
  'station position set to 14.60000, 120.99000', 'and the change is audited');

-- ------------------------------------------- road hazards for routing

-- Three open incidents become two confirmed floods and a confirmed fire.
create temp table __haz as
  select incident_id, row_number() over (order by incident_id) as n
    from public.incident_report
   where status <> 'resolved' and not cancelled
   order by incident_id limit 3;
update public.incident_report i
   set emergency_type = case when h.n = 3 then 'fire' else 'flood' end,
       verification_method = 'callback', false_report = false
  from __haz h where i.incident_id = h.incident_id;
update public.response_unit set current_incident_id = null where unit_id = 'unit-r05';
update public.staff set unit_id = 'unit-r05' where id = '00000000-0000-4000-8000-00000000000b';
create temp table __haz_n as
  select count(*)::int as n from public.incident_report i
   where coalesce(i.emergency_type, i.suggested_type) in ('flood', 'fire')
     and (i.verification_method is not null or i.origin = 'crowdCluster')
     and i.status <> 'resolved' and not i.false_report and not i.cancelled;
grant select on __haz, __haz_n to authenticated;

select ok(
  not has_function_privilege('anon', 'public.road_hazards()', 'execute')
  and has_function_privilege('authenticated', 'public.road_hazards()', 'execute'),
  'anon cannot ask where the floods and fires are');
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select throws_ok($$ select * from public.road_hazards() $$,
  'P0001', 'not_allowed', 'a resident is refused');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000e", "role": "authenticated"}';
select throws_ok($$ select * from public.road_hazards() $$,
  'P0001', 'not_allowed', 'an account with no role is refused');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}';
select is((select count(*)::int from public.road_hazards()), (select n from __haz_n),
  'a responder gets every confirmed open flood and fire');
select is((select string_agg(distinct type, ',' order by type) from public.road_hazards()),
  'fire,flood', 'with its type, and nothing else but the position');
reset role;
update public.response_unit set current_incident_id = (select incident_id from __haz where n = 1)
 where unit_id = 'unit-r05';
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}';
select is((select count(*)::int from public.road_hazards()), (select n - 1 from __haz_n),
  'never the unit''s own incident');
reset role;
update public.incident_report set false_report = true
 where incident_id = (select incident_id from __haz where n = 2);
update public.incident_report set cancelled = true
 where incident_id = (select incident_id from __haz where n = 3);
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}';
select is((select count(*)::int from public.road_hazards()), (select n - 3 from __haz_n),
  'a false report and a cancelled SOS no longer slow any road');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select is((select count(*)::int from public.road_hazards()), (select n - 2 from __haz_n),
  'a dispatcher gets them all (no incident of their own to leave out)');

-- ----------------------------------- confirmed incidents on Facebook

reset role;
select ok(
  not has_table_privilege('anon', 'public.incident_post', 'select')
  and not has_function_privilege('authenticated', 'public.claim_incident_posts()', 'execute')
  and not has_function_privilege('authenticated', 'public.finish_incident_post(bigint, text, text)', 'execute')
  and has_function_privilege('service_role', 'public.claim_incident_posts()', 'execute'),
  'only the sender (service role) can claim incident posts or record outcomes');

-- Four unverified SOS in Pandacan: three floods (the third simulated) and
-- a medical one.
insert into public.incident_report
select (jsonb_populate_record(null::public.incident_report,
         to_jsonb(i) || jsonb_build_object(
           'incident_id', 'INC-POST-' || g, 'client_uuid', gen_random_uuid(),
           'origin', 'sos', 'status', 'pendingVerification',
           'verification_method', null, 'emergency_type', null,
           'suggested_type', case g when 4 then 'medical' else 'flood' end,
           'false_report', false, 'cancelled', false, 'is_simulated', g = 3,
           'district', 'Pandacan', 'barangay', 'Barangay 840', 'address', '12 Sample Street',
           'assigned_unit_id', null, 'resolved_at', null, 'manila_resident_id', null))).*
  from (select * from public.incident_report order by incident_id limit 1) i,
       generate_series(1, 4) g;
select is((select count(*)::int from public.incident_post where incident_id like 'INC-POST-%'), 0,
  'an unverified SOS is never posted');

update public.incident_report set verification_method = 'callback' where incident_id = 'INC-POST-1';
select is((select status from public.incident_post where incident_id = 'INC-POST-1'), 'off',
  'with the switch off a confirmed incident is logged, not posted');

update public.app_setting set value = 'true' where key = 'channels.facebook_incidents';
update public.incident_report set verification_method = 'callback' where incident_id = 'INC-POST-2';
select ok(
  (select p.status = 'queued'
      and p.message like 'Confirmed flooding in Pandacan.%'
      and p.message like '%, confirmed at %'
      and position('Barangay' in p.message) = 0
      and position('Sample Street' in p.message) = 0
     from public.incident_post p where p.incident_id = 'INC-POST-2'),
  'with it on, the post says what, the district, and when: no barangay, no address');
update public.incident_report set emergency_type = 'fire' where incident_id = 'INC-POST-2';
select is(
  (select count(*)::int || ' ' || min(left(message, 26)) from public.incident_post where incident_id = 'INC-POST-2'),
  '1 Confirmed fire in Pandacan', 'one post per incident; a change of type rewrites its words');
update public.incident_report set verification_method = 'callback' where incident_id = 'INC-POST-3';
select is((select status from public.incident_post where incident_id = 'INC-POST-3'), 'simulated',
  'a simulated incident is logged as simulated and never posted');
update public.incident_report set verification_method = 'callback' where incident_id = 'INC-POST-4';
select is((select count(*)::int from public.incident_post where incident_id = 'INC-POST-4'), 0,
  'a medical emergency is never posted');

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select is((select count(*)::int from public.incident_post where incident_id like 'INC-POST-%'), 3,
  'dispatchers see what was posted, held back, or simulated');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is((select count(*)::int from public.incident_post), 0, 'residents see none of it');
reset role;

create temp table __posts as select public.claim_incident_posts() as claimed;
select is(
  (select string_agg(e ->> 'incident_id', ',') from __posts, jsonb_array_elements(claimed) e
    where e ->> 'incident_id' like 'INC-POST-%'),
  'INC-POST-2', 'the sender is handed only the queued post');
select public.finish_incident_post(
  (select post_id from public.incident_post where incident_id = 'INC-POST-2'), 'sent', 'post 1_2');
select public.finish_incident_post(
  (select post_id from public.incident_post where incident_id = 'INC-POST-2'), 'failed', 'again');
select is((select status || ' ' || detail from public.incident_post where incident_id = 'INC-POST-2'),
  'sent post 1_2', 'the outcome is recorded once');
select throws_ok(
  $$ select public.finish_incident_post(1, 'queued', null) $$,
  'P0001', 'invalid_value', 'only a final outcome can be recorded');
update public.incident_post set status = 'queued' where incident_id = 'INC-POST-1';
update public.incident_report set false_report = true where incident_id = 'INC-POST-1';
create temp table __posts_again as select public.claim_incident_posts() as claimed;
select is(
  (select (select count(*)::int from __posts_again, jsonb_array_elements(claimed) e
            where e ->> 'incident_id' = 'INC-POST-1')
          || ' ' || (select status from public.incident_post where incident_id = 'INC-POST-1')),
  '0 withdrawn', 'a report marked false before it was posted is withdrawn, not posted');

-- ----------------------------------- incident posts follow the incident

reset role;
select ok(
  not has_function_privilege('authenticated', 'public.record_incident_post(bigint, text, text, text, text)', 'execute')
  and has_function_privilege('service_role', 'public.record_incident_post(bigint, text, text, text, text)', 'execute'),
  'only the sender records what the Page accepted');

-- Two more unverified flood SOS in Pandacan.
insert into public.incident_report
select (jsonb_populate_record(null::public.incident_report,
         to_jsonb(i) || jsonb_build_object(
           'incident_id', 'INC-POST-' || g, 'client_uuid', gen_random_uuid(),
           'origin', 'sos', 'status', 'pendingVerification',
           'verification_method', null, 'emergency_type', null, 'suggested_type', 'flood',
           'false_report', false, 'cancelled', false, 'is_simulated', false, 'real_emergency', null,
           'district', 'Pandacan', 'barangay', 'Barangay 840', 'address', '12 Sample Street',
           'assigned_unit_id', null, 'resolved_at', null, 'manila_resident_id', null))).*
  from (select * from public.incident_report order by incident_id limit 1) i,
       generate_series(5, 6) g;
update public.incident_report set assigned_unit_id = 'unit-r03' where incident_id in ('INC-POST-5', 'INC-POST-6');
select ok(
  (select p.stage = 'unverified' and p.status = 'queued'
      and p.message like 'Unverified report: possible flooding in Pandacan.%'
     from public.incident_post p where p.incident_id = 'INC-POST-5'),
  'an unverified SOS is posted once a unit is sent, marked unverified');

-- The Page takes both posts.
create temp table __first as select public.claim_incident_posts() as claimed;
select public.record_incident_post(p.post_id, 'sent', 'post 1_' || right(p.incident_id, 1),
                                   '1_' || right(p.incident_id, 1), p.message)
  from public.incident_post p where p.incident_id in ('INC-POST-5', 'INC-POST-6');

update public.incident_report set verification_method = 'callback' where incident_id = 'INC-POST-5';
select is(
  (select stage || ' ' || status || ' ' || fb_post_id || ' ' || left(message, 30)
     from public.incident_post where incident_id = 'INC-POST-5'),
  'confirmed queued 1_5 Confirmed flooding in Pandacan',
  'verified: the same post is queued to be edited to confirmed');
create temp table __edit as select public.claim_incident_posts() as claimed;
select is(
  (select e ->> 'fb_post_id' from __edit, jsonb_array_elements(claimed) e
    where e ->> 'incident_id' = 'INC-POST-5'),
  '1_5', 'the sender is told which Page post to edit');
select public.record_incident_post(post_id, 'sent', 'edited', null, message)
  from public.incident_post where incident_id = 'INC-POST-5';

update public.incident_report set status = 'resolved', resolved_at = now() where incident_id = 'INC-POST-5';
select ok(
  (select status = 'queued' and message like '%responders have finished. The area is clear.%'
     from public.incident_post where incident_id = 'INC-POST-5'),
  'resolved: the post gets an update line');

update public.incident_report set real_emergency = false where incident_id = 'INC-POST-6';
select ok(
  (select stage = 'falseAlarm' and status = 'queued' and fb_post_id = '1_6'
      and message like 'False alarm: no flooding in Pandacan.%'
     from public.incident_post where incident_id = 'INC-POST-6'),
  'not a real emergency after it was posted: the post is edited to a false alarm');

create temp table __stale as select public.claim_incident_posts() as claimed;
select public.record_incident_post(post_id, 'sent', 'edited', null, 'older words')
  from public.incident_post where incident_id = 'INC-POST-6';
select is((select status from public.incident_post where incident_id = 'INC-POST-6'), 'queued',
  'an outcome for older words puts the post back in the queue');

-- A cancelled SOS is not a false alarm.
insert into public.incident_report
select (jsonb_populate_record(null::public.incident_report,
         to_jsonb(i) || jsonb_build_object(
           'incident_id', 'INC-POST-' || g, 'client_uuid', gen_random_uuid(),
           'origin', 'sos', 'status', 'pendingVerification',
           'verification_method', null, 'emergency_type', null, 'suggested_type', 'fire',
           'false_report', false, 'cancelled', false, 'is_simulated', false, 'real_emergency', null,
           'district', 'Tondo', 'barangay', 'Barangay 105', 'address', '3 Sample Street',
           'assigned_unit_id', 'unit-r03', 'resolved_at', null, 'manila_resident_id', null))).*
  from (select * from public.incident_report order by incident_id limit 1) i,
       generate_series(7, 8) g;
create temp table __third as select public.claim_incident_posts() as claimed;
select public.record_incident_post(post_id, 'sent', 'posted', '1_' || right(incident_id, 1), message)
  from public.incident_post where incident_id in ('INC-POST-7', 'INC-POST-8');
update public.incident_report set verification_method = 'callback' where incident_id = 'INC-POST-7';
update public.incident_report set cancelled = true, cancel_reason = 'safeNow', status = 'resolved', resolved_at = now()
 where incident_id in ('INC-POST-7', 'INC-POST-8');
select ok(
  (select bool_and(case p.incident_id
      when 'INC-POST-7' then p.stage = 'confirmed' and p.message like '%the person who asked for help is safe%'
                             and p.message not like '%False alarm%'
      else p.stage = 'withdrawn' and p.message like 'Update: report withdrawn.%'
                             and p.message like '%withdrawn by the person who made it%' end)
     from public.incident_post p where p.incident_id in ('INC-POST-7', 'INC-POST-8')), 
  'a cancelled SOS is never called a false alarm: confirmed ones say the person is safe, others say withdrawn');


-- ------------------------------------------------------ safe places

-- Six places around one point (14.6000, 120.9900), with the loaded ones
-- hidden so only these count: a school 100 m north, a basketball court
-- 50 m north, a hospital 200 m north, a park 440 m north, a covered court
-- 350 m east, and a hidden evacuation center 50 m south.
reset role;
update public.safe_place set hidden_at = now() where hidden_at is null;
-- No other confirmed open flood or fire may leave a test place out.
update public.incident_report set false_report = true
 where coalesce(emergency_type, suggested_type) in ('flood', 'fire')
   and status <> 'resolved' and not cancelled and not false_report;
insert into public.safe_place (place_id, name, kind, latitude, longitude, barangay, district, source, hidden_at) values
  ('adm-00000000a1', 'Test School', 'school', 14.6009, 120.9900, 'Barangay 400', 'Sampaloc', 'test', null),
  ('adm-00000000b2', null, 'basketballCourt', 14.60045, 120.9900, 'Barangay 400', 'Sampaloc', 'test', null),
  ('adm-00000000c3', 'Test Hospital', 'hospital', 14.6018, 120.9900, 'Barangay 400', 'Sampaloc', 'test', null),
  ('adm-00000000d4', 'Test Park', 'openSpace', 14.6040, 120.9900, 'Barangay 400', 'Sampaloc', 'test', null),
  ('adm-00000000e5', 'Test Covered Court', 'coveredCourt', 14.6000, 120.99325, 'Barangay 400', 'Sampaloc', 'test', null),
  ('adm-00000000f6', 'Test Hidden Center', 'evacuationCenter', 14.59955, 120.9900, 'Barangay 400', 'Sampaloc', 'test', now());

select ok(
  not has_table_privilege('anon', 'public.safe_place', 'select')
  and has_table_privilege('authenticated', 'public.safe_place', 'select')
  and not has_table_privilege('authenticated', 'public.safe_place', 'insert')
  and not has_table_privilege('authenticated', 'public.safe_place', 'update')
  and not has_table_privilege('authenticated', 'public.safe_place', 'delete'),
  'safe places: signed-in users may only read; changes go through the admin functions');
select ok(
  not has_function_privilege('anon', 'public.safe_places_near(double precision, double precision, text, int)', 'execute')
  and not has_function_privilege('anon', 'public.save_safe_place(text, text, text, double precision, double precision, boolean)', 'execute')
  and not has_function_privilege('anon', 'public.set_safe_place_hidden(text, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'private.safe_kinds(text)', 'execute'),
  'anon can call none of the safe place functions; the rule helpers are private');

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is(
  (select string_agg(place_id, ',' order by place_id) from public.safe_place where source = 'test'),
  'adm-00000000a1,adm-00000000b2,adm-00000000c3,adm-00000000d4,adm-00000000e5',
  'a resident reads the visible places, never a hidden one');
select is(
  (select string_agg(place_id, ',') from public.safe_places_near(14.6000, 120.9900, 'flood')),
  'adm-00000000a1,adm-00000000e5',
  'flood: somewhere high (a school, a covered court), nearest first; never open ground or a hidden place');
select is(
  (select string_agg(place_id, ',') from public.safe_places_near(14.6000, 120.9900, 'fire')),
  'adm-00000000e5,adm-00000000d4',
  'fire: open ground at least 300 m from the fire');
select is(
  (select string_agg(place_id, ',') from public.safe_places_near(14.6000, 120.9900, 'structural')),
  'adm-00000000d4',
  'collapse: open ground at least 100 m away, not a covered court');
select is(
  (select string_agg(place_id, ',') from public.safe_places_near(14.6000, 120.9900, 'medical')),
  'adm-00000000c3',
  'medical: a hospital');
select is(
  (select count(*)::int from public.safe_places_near(14.6000, 120.9900, 'fire', 1)),
  1, 'the limit is kept');
select is(
  (select round(meters)::int from public.safe_places_near(14.6000, 120.9900, 'medical')),
  199, 'with the straight-line distance in meters');
select throws_ok($$ select * from public.safe_places_near(14.6000, 120.9900, 'earthquake') $$,
  'P0001', 'invalid_value', 'an emergency with no rule is refused');
select throws_ok(
  $$ update public.safe_place set hidden_at = now() where place_id = 'adm-00000000a1' $$,
  '42501', null, 'a resident cannot hide a place directly');
select throws_ok(
  $$ select public.save_safe_place(null, 'Mine', 'school', 14.6, 120.99, false) $$,
  'P0001', 'not_allowed', 'a resident cannot add a place');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select is(
  (select count(*)::int from public.safe_place where source = 'test'), 6,
  'a dispatcher also reads the hidden place');
select throws_ok(
  $$ select public.set_safe_place_hidden('adm-00000000a1', true) $$,
  'P0001', 'not_allowed', 'a dispatcher cannot hide a place');

-- A confirmed open flood at the school, then a confirmed open fire at the park.
reset role;
insert into public.incident_report
select (jsonb_populate_record(null::public.incident_report,
         to_jsonb(i) || jsonb_build_object(
           'incident_id', 'INC-SAFE-' || g, 'client_uuid', gen_random_uuid(),
           'origin', 'sos', 'status', 'pendingVerification',
           'verification_method', null, 'emergency_type', null, 'suggested_type', null,
           'false_report', false, 'cancelled', false, 'is_simulated', false, 'real_emergency', null,
           'latitude', case g when 1 then 14.6009 else 14.6040 end, 'longitude', 120.9900,
           'district', 'Sampaloc', 'barangay', 'Barangay 400', 'address', null,
           'assigned_unit_id', null, 'resolved_at', null, 'manila_resident_id', null))).*
  from (select * from public.incident_report order by incident_id limit 1) i,
       generate_series(1, 2) g;
update public.incident_report
   set emergency_type = case incident_id when 'INC-SAFE-1' then 'flood' else 'fire' end
 where incident_id in ('INC-SAFE-1', 'INC-SAFE-2');
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is(
  (select string_agg(place_id, ',') from public.safe_places_near(14.6000, 120.9900, 'flood')),
  'adm-00000000a1,adm-00000000e5',
  'an unverified flood report leaves the places as they are');
reset role;
update public.incident_report set verification_method = 'callback'
 where incident_id in ('INC-SAFE-1', 'INC-SAFE-2');
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is(
  (select string_agg(place_id, ',') from public.safe_places_near(14.6000, 120.9900, 'flood')),
  'adm-00000000e5',
  'a place within 150 m of a confirmed open flood is left out');
select is(
  (select string_agg(place_id, ',') from public.safe_places_near(14.6000, 120.9900, 'fire')),
  'adm-00000000e5',
  'a place within 300 m of a confirmed open fire is left out');
reset role;
update public.incident_report set false_report = true where incident_id = 'INC-SAFE-1';
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is(
  (select string_agg(place_id, ',') from public.safe_places_near(14.6000, 120.9900, 'flood')),
  'adm-00000000a1,adm-00000000e5',
  'a false report no longer leaves anything out');

-- Admin (A2): add, edit, hide, show again; each one in the audit log.
reset role;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
create temp table __safe_new as
  select public.save_safe_place(null, '  Barangay 400 Evacuation Center ', 'evacuationCenter', 14.6002, 120.9902, true) as id;
grant select on __safe_new to authenticated;
set local role authenticated;
select ok(
  (select id ~ '^adm-[0-9a-f]{10}$' from __safe_new)
  and exists (select 1 from public.safe_place s, __safe_new n
               where s.place_id = n.id and s.name = 'Barangay 400 Evacuation Center'
                 and s.official and s.barangay is not null and s.district is not null
                 and s.updated_by = '00000000-0000-4000-8000-00000000000a'),
  'an admin adds an official evacuation center; its barangay comes from the position');
select ok(
  exists (select 1 from public.audit_log a, __safe_new n
           where a.action_type = 'safePlaceSaved' and a.target_id = n.id
             and a.account_id = '00000000-0000-4000-8000-00000000000a'),
  'adding a place is in the audit log');
select throws_ok(
  $$ select public.save_safe_place(null, 'Far away', 'school', 14.45, 120.99, false) $$,
  'P0001', 'outside_manila', 'a place outside Manila is refused');
select throws_ok(
  $$ select public.save_safe_place(null, '  ', 'evacuationCenter', 14.6002, 120.9902, true) $$,
  'P0001', 'invalid_value', 'an evacuation center needs a name');
select throws_ok(
  $$ select public.save_safe_place(null, 'Odd', 'mall', 14.6002, 120.9902, false) $$,
  'P0001', 'invalid_value', 'a kind with no rule is refused');
select lives_ok(
  $$ select public.save_safe_place('adm-00000000b2', 'Test Court', 'basketballCourt', 14.60045, 120.9900, false) $$,
  'an admin names a place from the map');
select ok(
  (select name = 'Test Court' and updated_by = '00000000-0000-4000-8000-00000000000a'
     from public.safe_place where place_id = 'adm-00000000b2')
  and exists (select 1 from public.audit_log where action_type = 'safePlaceSaved'
                 and target_id = 'adm-00000000b2' and detail like 'name (none) → Test Court%'),
  'the change is kept from a reload (updated_by) and in the audit log');
select lives_ok($$ select public.set_safe_place_hidden('adm-00000000a1', true) $$,
  'an admin hides a wrong place');
select ok(
  exists (select 1 from public.audit_log where action_type = 'safePlaceHidden' and target_id = 'adm-00000000a1'),
  'hiding is in the audit log');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is(
  (select string_agg(place_id, ',') from public.safe_places_near(14.6000, 120.9900, 'flood', 2)),
  (select n.id || ',adm-00000000e5' from __safe_new n),
  'a hidden place is no longer suggested; the new evacuation center is');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select lives_ok($$ select public.set_safe_place_hidden('adm-00000000a1', false) $$,
  'an admin shows it again');
select ok(
  exists (select 1 from public.audit_log where action_type = 'safePlaceRestored' and target_id = 'adm-00000000a1')
  and (select hidden_at is null from public.safe_place where place_id = 'adm-00000000a1'),
  'showing it again is in the audit log');



-- ------------------------------- a relayed SOS names its sender by its phone's key

reset role;
-- res-001 was left suspended above; a suspended resident's SOS is never
-- account-verified, so lift it for these checks.
update public.manila_resident set suspended_at = null where manila_resident_id = 'res-001';
select ok(
  not has_table_privilege('authenticated', 'public.relay_device', 'select')
  and not has_table_privilege('authenticated', 'public.relay_device', 'insert')
  and not has_table_privilege('anon', 'public.relay_device', 'select')
  and not has_function_privilege('anon', 'public.register_relay_key(text)', 'execute')
  and has_function_privilege('authenticated', 'public.register_relay_key(text)', 'execute')
  and not has_function_privilege('authenticated', 'private.relay_code(bytea, timestamptz, double precision, double precision, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'private.relay_device_for(uuid, timestamptz, double precision, double precision, boolean)', 'execute'),
  'no app reads the phones'' keys; a signed-in phone can only hand its own over');
-- The same example the app's test checks (packages/shared relay_id_test).
select is(
  private.relay_code(decode('0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20', 'hex'),
                     '2026-10-19T00:00:00Z', 14.6, 120.99, false)::text,
  '69f8feeb-181b-4e7e-861b-70b3ebdd9053', 'the code matches the app''s (with a place)');
select is(
  private.relay_code(decode('0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20', 'hex'),
                     '2026-10-19T00:00:00Z', null, null, true)::text,
  '26b90c86-a71a-406e-91b0-11ddfc11e4c4', 'the code matches the app''s (no place, mock)');

create temp table __rk as
  select k.secret, k.t,
         private.relay_code(k.secret, k.t, 14.6000, 120.9900, false) as sos1,
         private.relay_code(k.secret, k.t + interval '10 seconds', null, null, false) as sos2,
         private.relay_code(k.secret, k.t + interval '20 seconds', 14.6000, 120.9900, false) as sos3,
         private.relay_code(k.secret, k.t + interval '30 seconds', 14.6000, 120.9900, false) as sos4
    from (select decode('0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20', 'hex') as secret,
                 date_trunc('second', now()) - interval '3 minutes' as t) k;
grant select on __rk to authenticated;

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}';
select throws_ok($$ select public.register_relay_key(repeat('ab', 32)) $$,
  'P0001', 'not_allowed', 'only a resident''s phone hands over a key');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select throws_ok($$ select public.register_relay_key('not-a-key') $$,
  'P0001', 'invalid_value', 'a key that is not 32 bytes in hex is refused');
create temp table __dev as
  select public.register_relay_key(encode(secret, 'hex')) as id from __rk;
select is((select public.register_relay_key(encode(secret, 'hex')) from __rk), (select id from __dev),
  'handing the same key over again changes nothing');

-- A responder's phone heard res-001's SOS and uploads it.
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}';
select is(
  (select public.relay_sos(sos1, t, 14.6000, 120.9900, false, 1) ->> 'duplicate' from __rk),
  'false', 'an SOS relayed over Bluetooth is filed');
select is(
  (select public.relay_sos(sos2, t + interval '10 seconds', null, null, false, 2) ->> 'duplicate' from __rk),
  'false', 'one with no position is filed too');
select is(
  (select public.relay_sos(sos3, t + interval '21 seconds', 14.6000, 120.9900, false, 1) ->> 'duplicate' from __rk),
  'false', 'one whose time was changed on the way is filed');
reset role;
select ok(
  (select i.manila_resident_id = 'res-001' and i.channel = 'bleRelay' and i.account_verified
          and i.status = 'pendingVerification'
          and i.vulnerable = private.resident_vulnerable(r)
     from public.incident_report i, public.manila_resident r, __rk k
    where i.client_uuid = k.sos1 and r.manila_resident_id = 'res-001'),
  'the phone''s key names the real sender (not the phone that carried it); the SOS stays pending');
select ok(
  (select i.manila_resident_id = 'res-001' and i.barangay = r.barangay
     from public.incident_report i, public.manila_resident r, __rk k
    where i.client_uuid = k.sos2 and r.manila_resident_id = 'res-001'),
  'with no position in the packet it is placed in the sender''s home barangay');
select ok(
  (select i.manila_resident_id is null and not i.account_verified
     from public.incident_report i, __rk k where i.client_uuid = k.sos3),
  'a changed packet no longer matches: it comes from an unknown sender (it cannot be faked)');
select is(
  (select relayed_by::text from public.sos_relay_log l, __rk k where l.client_uuid = k.sos1),
  '00000000-0000-4000-8000-00000000000b', 'the log keeps who carried it');
select ok(
  (select last_used_at is not null from public.relay_device d, __dev v where d.device_id = v.id),
  'the phone''s key was used');

-- The resident's own phone gets online and sends its copy.
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is(
  (select public.submit_sos(sos1, t, 14.6000, 120.9900, 8) from __rk),
  (select incident_id from public.incident_report i, __rk k where i.client_uuid = k.sos1),
  'the resident''s own copy is the same incident');

-- Five newer phones: the oldest key is retired and names no one.
select lives_ok($$
  select public.register_relay_key(encode(sha256(convert_to('phone ' || g, 'UTF8')), 'hex')) from generate_series(1, 5) g
$$, 'a resident registers five more phones');
reset role;
select ok(
  (select revoked_at is not null from public.relay_device d, __dev v where d.device_id = v.id)
  and (select count(*) = 5 from public.relay_device
        where manila_resident_id = 'res-001' and revoked_at is null),
  'a resident keeps five phones; the oldest is retired');
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}';
select is(
  (select public.relay_sos(sos4, t + interval '30 seconds', 14.6000, 120.9900, false, 1) ->> 'duplicate' from __rk),
  'false', 'an SOS from a retired phone is still filed');
reset role;
select ok(
  (select manila_resident_id is null from public.incident_report i, __rk k where i.client_uuid = k.sos4),
  'but from an unknown sender');

-- ------------------------------------------------ the oldest app allowed

set local role anon;
select is((public.client_config() ->> 'min_build')::int, 1, 'any app can read the oldest build allowed');
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select throws_ok($$ select public.set_setting('app.min_build', '0'::jsonb) $$,
  'P0001', 'invalid_value', 'the oldest build allowed is at least 1');
select lives_ok($$ select public.set_setting('app.min_build', '2'::jsonb) $$,
  'an admin raises it');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select throws_ok($$ select public.set_setting('app.min_build', '3'::jsonb) $$,
  'P0001', 'not_allowed', 'a dispatcher cannot');
reset role;
select is((public.client_config() ->> 'min_build')::int, 2, 'and the apps see the new value');


-- ------------------------------------------- photos on an SOS or a report

reset role;
update public.manila_resident set suspended_at = null where manila_resident_id = 'res-001';
select ok(
  not has_table_privilege('anon', 'public.incident_photo', 'select')
  and has_table_privilege('authenticated', 'public.incident_photo', 'select')
  and not has_table_privilege('authenticated', 'public.incident_photo', 'insert')
  and not has_function_privilege('anon', 'public.attach_photo(uuid, text, uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.attach_photo(uuid, text, uuid)', 'execute'),
  'photos: signed-in users only read; a photo is tied to a record through attach_photo');
-- Another resident's SOS, and one of res-001's crowd reports.
create temp table __ph as
  select (select client_uuid from public.incident_report
           where manila_resident_id is distinct from 'res-001' and client_uuid is not null
           order by incident_id limit 1) as other_sos;
grant select on __ph to authenticated;
insert into public.crowd_report
select (jsonb_populate_record(null::public.crowd_report,
         to_jsonb(c) || jsonb_build_object(
           'report_id', 'rep-PHOTO-1', 'manila_resident_id', 'res-001',
           'client_uuid', '00000000-0000-4000-8000-0000000009c1', 'anonymized_at', null))).*
  from (select * from public.crowd_report order by report_id limit 1) c;

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select public.submit_sos('00000000-0000-4000-8000-0000000009b1', now(), 14.6000, 120.9900, 8);
select lives_ok($$
  insert into storage.objects (bucket_id, name) values
    ('incident-photos', '00000000-0000-4000-8000-00000000000c/00000000-0000-4000-8000-0000000009a1.jpg'),
    ('incident-photos', '00000000-0000-4000-8000-00000000000c/00000000-0000-4000-8000-0000000009a2.jpg'),
    ('incident-photos', '00000000-0000-4000-8000-00000000000c/00000000-0000-4000-8000-0000000009a3.jpg'),
    ('incident-photos', '00000000-0000-4000-8000-00000000000c/00000000-0000-4000-8000-0000000009a4.jpg'),
    ('incident-photos', '00000000-0000-4000-8000-00000000000c/00000000-0000-4000-8000-0000000009a5.jpg')
$$, 'a resident uploads photos into their own folder');
select throws_ok($$
  insert into storage.objects (bucket_id, name)
  values ('incident-photos', '00000000-0000-4000-8000-00000000000e/00000000-0000-4000-8000-0000000009a9.jpg')
$$, '42501', null, 'but not into another account''s folder');
select is(
  public.attach_photo('00000000-0000-4000-8000-0000000009a1', 'sos', '00000000-0000-4000-8000-0000000009b1'),
  '00000000-0000-4000-8000-0000000009a1'::uuid, 'a photo is tied to the resident''s own SOS');
select is(
  public.attach_photo('00000000-0000-4000-8000-0000000009a1', 'sos', '00000000-0000-4000-8000-0000000009b1'),
  '00000000-0000-4000-8000-0000000009a1'::uuid, 'sending it again changes nothing');
select throws_ok(
  $$ select public.attach_photo('00000000-0000-4000-8000-0000000009a2', 'sos', (select other_sos from __ph)) $$,
  'P0001', 'not_found', 'not to someone else''s SOS');
select throws_ok(
  $$ select public.attach_photo('00000000-0000-4000-8000-0000000009a8', 'sos', '00000000-0000-4000-8000-0000000009b1') $$,
  'P0001', 'not_found', 'not without the uploaded file');
select lives_ok($$
  select public.attach_photo('00000000-0000-4000-8000-0000000009a2', 'sos', '00000000-0000-4000-8000-0000000009b1'),
         public.attach_photo('00000000-0000-4000-8000-0000000009a3', 'sos', '00000000-0000-4000-8000-0000000009b1')
$$, 'up to three on one SOS');
select throws_ok(
  $$ select public.attach_photo('00000000-0000-4000-8000-0000000009a4', 'sos', '00000000-0000-4000-8000-0000000009b1') $$,
  'P0001', 'invalid_value', 'a fourth is refused');
select is(
  public.attach_photo('00000000-0000-4000-8000-0000000009a5', 'report', '00000000-0000-4000-8000-0000000009c1'),
  '00000000-0000-4000-8000-0000000009a5'::uuid, 'and one on the resident''s own crowd report');
select is((select count(*)::int from public.incident_photo), 4, 'the resident sees their own photos');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}';
select throws_ok($$
  insert into storage.objects (bucket_id, name)
  values ('incident-photos', '00000000-0000-4000-8000-00000000000b/00000000-0000-4000-8000-0000000009a7.jpg')
$$, '42501', null, 'a staff account uploads no photos');
select is((select count(*)::int from public.incident_photo), 0,
  'a responder whose unit is not on the incident sees none');
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000e", "role": "authenticated"}';
select is((select count(*)::int from public.incident_photo), 0, 'another account sees none');
select is((select count(*)::int from storage.objects where bucket_id = 'incident-photos'), 0,
  'nor their files');

reset role;
create temp table __phi as
  select incident_id from public.incident_report where client_uuid = '00000000-0000-4000-8000-0000000009b1';
grant select on __phi to authenticated;
update public.crowd_report set incident_id = (select incident_id from __phi) where report_id = 'rep-PHOTO-1';
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select is((select count(*)::int from public.incident_photos((select incident_id from __phi))), 4,
  'a dispatcher gets the SOS''s photos and those of the reports in its cluster');
select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'incident-photos' and name like '00000000-0000-4000-8000-00000000000c/%'),
  4, 'and can open their files (not the one never tied to a record)');

reset role;
update public.incident_report set assigned_unit_id = 'unit-r05', status = 'assigned'
 where incident_id = (select incident_id from __phi);
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}';
select is((select count(*)::int from public.incident_photos((select incident_id from __phi))), 4,
  'the responders of the assigned unit see them');

reset role;
update public.incident_report set status = 'resolved', resolved_at = now()
 where incident_id = (select incident_id from __phi);
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select throws_ok(
  $$ select public.attach_photo('00000000-0000-4000-8000-0000000009a4', 'sos', '00000000-0000-4000-8000-0000000009b1') $$,
  'P0001', 'incident_closed', 'no photo on a closed SOS');

reset role;
update public.incident_report set anonymized_at = now() where incident_id = (select incident_id from __phi);
update public.crowd_report set anonymized_at = now() where report_id = 'rep-PHOTO-1';
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select is((select count(*)::int from public.incident_photos((select incident_id from __phi))), 0,
  'retention hides the photos from everyone (RA 10173)');
select is(
  (select count(*)::int from storage.objects
    where bucket_id = 'incident-photos' and name like '00000000-0000-4000-8000-00000000000c/%'),
  0, 'and their files');

-- ---------------------------------------------- crew and personnel IDs
-- Crew lists (2026-10-28): names and MDRRMD personnel IDs per unit.

reset role;
select ok(not has_function_privilege('anon', 'public.unit_crew()', 'execute'),
  'anon cannot read crew lists');
select ok(not has_function_privilege('anon', 'public.admin_set_personnel_id(uuid, text)', 'execute'),
  'anon cannot set personnel IDs');
update public.staff set unit_id = 'unit-r05', deactivated_at = null
 where id = '00000000-0000-4000-8000-00000000000b';
update public.staff set unit_id = null, deactivated_at = null
 where id = '00000000-0000-4000-8000-000000000011';

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000a", "role": "authenticated"}';
select lives_ok(
  $$ select public.admin_set_personnel_id('00000000-0000-4000-8000-00000000000b', ' mdrrmd-0142 ') $$,
  'an admin sets a personnel ID');
select is(
  (select personnel_id from public.staff where id = '00000000-0000-4000-8000-00000000000b'),
  'MDRRMD-0142', 'stored trimmed and in capitals');
select throws_ok(
  $$ select public.admin_set_personnel_id('00000000-0000-4000-8000-000000000011', 'MDRRMD-0142') $$,
  'P0001', 'already_exists', 'no two accounts share a personnel ID');
select throws_ok(
  $$ select public.admin_set_personnel_id('00000000-0000-4000-8000-000000000011', 'ID 42!') $$,
  'P0001', 'invalid_value', 'a personnel ID is letters, digits, and dashes');
select ok(
  exists (select 1 from public.audit_log
    where account_name = 'Test Admin' and action_type = 'accountUpdated'
      and target_id = '00000000-0000-4000-8000-00000000000b' and detail like 'personnel ID none → MDRRMD-0142%'),
  'setting a personnel ID is audited');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select throws_ok(
  $$ select public.admin_set_personnel_id('00000000-0000-4000-8000-00000000000b', 'X-1') $$,
  'P0001', 'not_allowed', 'a dispatcher cannot set personnel IDs (admins only)');
select ok(
  exists (select 1 from public.unit_crew()
    where unit_id = 'unit-r05' and display_name = 'Test Responder' and personnel_id = 'MDRRMD-0142'),
  'a dispatcher sees a unit''s crew with their personnel IDs');
select is(
  (select count(*)::int from public.unit_crew() where staff_id = '00000000-0000-4000-8000-000000000011'),
  0, 'a responder on no unit is in no crew list');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000b", "role": "authenticated"}';
select ok(
  exists (select 1 from public.unit_crew() where staff_id = '00000000-0000-4000-8000-00000000000b'),
  'a responder sees their own unit''s crew, themself included');
select is(
  (select count(*)::int from public.unit_crew() where unit_id <> 'unit-r05'),
  0, 'and no other unit''s crew');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000c", "role": "authenticated"}';
select is((select count(*)::int from public.unit_crew()), 0, 'a resident sees no crew');

set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-000000000011", "role": "authenticated"}';
select is((select count(*)::int from public.unit_crew()), 0,
  'a responder on no unit sees no crew');

reset role;
update public.staff set deactivated_at = now() where id = '00000000-0000-4000-8000-00000000000b';
set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-00000000000d", "role": "authenticated"}';
select is(
  (select count(*)::int from public.unit_crew() where staff_id = '00000000-0000-4000-8000-00000000000b'),
  0, 'a deactivated responder leaves the crew list');
reset role;
update public.staff set deactivated_at = null where id = '00000000-0000-4000-8000-00000000000b';

-- The counters as the real records need them (see the top).
reset role;
select setval(seq, last_value) from __counters;

reset role;
select * from finish();
rollback;
