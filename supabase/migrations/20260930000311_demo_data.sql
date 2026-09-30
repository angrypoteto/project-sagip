-- Demo data and demo tools. Run these from the Supabase SQL editor:
--
--   select public.reset_demo_data();        -- wipe incidents/reports/residents/units and reload the sample data
--   select public.demo_new_sos();           -- a new SOS arrives (Barangay 128, Tondo, flagged mock location)
--   select public.demo_add_crowd_report();  -- a third Dapitan St report: DBSCAN turns it into a confirmed incident
--   select public.demo_advance();           -- move every assigned incident one step: en route, on scene, resolved
--   select public.create_staff_account('email', 'password', 'Name', 'dispatcher' | 'admin' | 'responder');
--
-- All names and numbers are fictional. The app cannot call these functions.

create or replace function public.create_staff_account(
  p_email text,
  p_password text,
  p_display_name text,
  p_role text,
  p_unit_id text default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid;
  email_lc text := lower(btrim(p_email));
begin
  if p_role not in ('dispatcher', 'admin', 'responder') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select u.id into uid from auth.users u where u.email = email_lc;
  if uid is null then
    uid := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', email_lc,
      extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
      '{"provider": "email", "providers": ["email"]}',
      jsonb_build_object('display_name', p_display_name), now(), now(), '', '', '', ''
    );
    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), uid, uid::text,
      jsonb_build_object('sub', uid::text, 'email', email_lc, 'email_verified', true),
      'email', now(), now(), now()
    );
  else
    update auth.users
       set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
           updated_at = now()
     where id = uid;
  end if;
  insert into public.staff (id, display_name, email, role, unit_id)
  values (uid, p_display_name, email_lc, p_role, p_unit_id)
  on conflict (id) do update
    set display_name = excluded.display_name, role = excluded.role, unit_id = excluded.unit_id;
  return uid;
end $$;

create or replace function public.reset_demo_data()
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  t0 timestamptz := now();
  dispatcher_id text := coalesce(
    (select s.id::text from public.staff s where s.role = 'dispatcher' order by s.created_at limit 1),
    'seed'
  );
  dispatcher_name text := coalesce(
    (select s.display_name from public.staff s where s.role = 'dispatcher' order by s.created_at limit 1),
    'R. Santos'
  );
begin
  -- Clear domain data. Staff accounts are kept.
  update public.response_unit set current_incident_id = null;
  delete from public.dispatch;
  delete from public.incident_event;
  delete from public.crowd_report;
  delete from public.incident_report;
  delete from public.vulnerable_member;
  delete from public.manila_resident;
  update public.staff set unit_id = null;
  delete from public.response_unit;
  delete from public.weather_alert;
  delete from public.audit_log;

  -- Residents and the Vulnerable Resident Priority List.
  insert into public.manila_resident
    (manila_resident_id, fullname, contact_number, barangay, district, consent_given_at, updated_at)
  values
    ('res-001', 'Maria Dela Cruz', '0917 000 4821', 'Barangay 412', 'Sampaloc', t0 - interval '40 days', t0 - interval '12 days'),
    ('res-002', 'Jose Ramos', '0918 000 3310', 'Barangay 649', 'Port Area', null, t0 - interval '30 days'),
    ('res-003', 'Ana Santos', '0919 000 7712', 'Barangay 700', 'Malate', t0 - interval '90 days', t0 - interval '90 days'),
    ('res-004', 'Rosa Villanueva', '0920 000 1187', 'Barangay 128', 'Tondo', t0 - interval '21 days', t0 - interval '21 days'),
    ('res-005', 'Carlos Reyes', '0921 000 6604', 'Barangay 105', 'Tondo', t0 - interval '55 days', t0 - interval '30 days'),
    ('res-006', 'Liza Mercado', '0922 000 2290', 'Barangay 306', 'Quiapo', t0 - interval '14 days', t0 - interval '14 days'),
    ('res-007', 'Benjie Cruz', '0923 000 5518', 'Barangay 560', 'Sampaloc', t0 - interval '7 days', t0 - interval '7 days'),
    ('res-008', 'Teresita Lim', '0924 000 9043', 'Barangay 287', 'Binondo', t0 - interval '120 days', t0 - interval '60 days');

  insert into public.vulnerable_member (manila_resident_id, label, vulnerability_types, notes) values
    ('res-001', 'Lolo Andres', array['seniorCitizen', 'pwd'], 'Uses a wheelchair'),
    ('res-003', 'Ana (self)', array['seniorCitizen'], null),
    ('res-004', 'Rosa (self)', array['pregnant'], '8 months'),
    ('res-005', 'Son', array['pwd'], 'Uses crutches'),
    ('res-006', 'Parents', array['seniorCitizen'], 'Both over 75'),
    ('res-007', 'Wife', array['pregnant'], null),
    ('res-008', 'Teresita (self)', array['seniorCitizen', 'pwd'], 'Hard of hearing');

  -- Units (status and incident links are set after incidents exist).
  insert into public.response_unit
    (unit_id, call_sign, unit_type, station, crew_size, status, last_latitude, last_longitude, last_location_at)
  values
    ('unit-r03', 'R-03', 'rescueBoat', 'Sampaloc station', 4, 'available', 14.6045, 121.0010, t0 - interval '20 seconds'),
    ('unit-r07', 'R-07', 'rescueTeam', 'Sampaloc station', 6, 'available', 14.6060, 121.0020, t0 - interval '20 seconds'),
    ('unit-a05', 'A-05', 'ambulance', 'Santa Cruz station', 3, 'available', 14.6190, 120.9840, t0 - interval '20 seconds'),
    ('unit-a02', 'A-02', 'ambulance', 'Binondo station', 3, 'available', 14.5990, 120.9790, t0 - interval '20 seconds'),
    ('unit-r05', 'R-05', 'rescueTeam', 'Malate station', 5, 'enRoute', 14.5780, 120.9880, t0 - interval '20 seconds'),
    ('unit-r11', 'R-11', 'rescueTeam', 'Sampaloc station', 6, 'onScene', 14.6110, 121.0000, t0 - interval '20 seconds'),
    ('unit-r02', 'R-02', 'rescueBoat', 'Tondo station', 4, 'available', 14.6150, 120.9650, t0 - interval '20 seconds'),
    ('unit-r04', 'R-04', 'rescueTeam', 'Port Area station', 5, 'available', 14.5900, 120.9720, t0 - interval '20 seconds'),
    ('unit-r09', 'R-09', 'rescueTeam', 'Paco station', 5, 'available', 14.5800, 121.0000, t0 - interval '20 seconds'),
    ('unit-a01', 'A-01', 'ambulance', 'Ermita station', 3, 'available', 14.5840, 120.9830, t0 - interval '20 seconds'),
    ('unit-a03', 'A-03', 'ambulance', 'Malate station', 3, 'available', 14.5700, 120.9920, t0 - interval '20 seconds'),
    ('unit-r12', 'R-12', 'rescueBoat', 'Santa Ana station', 4, 'available', 14.5820, 121.0120, t0 - interval '20 seconds');

  -- Incidents on the Triage Queue.
  insert into public.incident_report (
    incident_id, origin, channel, status, suggested_type, emergency_type,
    latitude, longitude, barangay, district, address, accuracy_m,
    captured_at, received_at, manila_resident_id, people_count, note, vulnerable,
    account_verified, verification_method, assigned_unit_id
  ) values
    ('INC-0147', 'sos', 'app', 'pendingVerification', 'flood', null,
     14.6091, 120.9925, 'Barangay 412', 'Sampaloc', '1482 Dapitan St', 8,
     t0 - interval '4 min 12 s', t0 - interval '4 min 11 s', 'res-001', 3,
     'Water is waist-deep inside the house.', array['seniorCitizen', 'pwd'], true, null, null),
    ('INC-0149', 'sos', 'sms', 'pendingVerification', null, null,
     14.5869, 120.9690, 'Barangay 649', 'Port Area', null, 15,
     t0 - interval '1 min 5 s', t0 - interval '1 min 1 s', 'res-002', null, null, '{}', true, null, null),
    ('INC-0146', 'crowdCluster', 'app', 'confirmed', 'flood', null,
     14.61972, 120.96706, 'Barangay 105', 'Tondo', 'Juan Luna St', null,
     t0 - interval '9 min', t0 - interval '6 min 40 s', null, null, null, '{}', false, null, null),
    ('INC-0144', 'sos', 'app', 'assigned', 'fire', 'fire',
     14.6003, 120.9745, 'Barangay 287', 'Binondo', 'Ongpin St', 11,
     t0 - interval '9 min 12 s', t0 - interval '9 min 11 s', 'res-008', 2, null,
     array['seniorCitizen', 'pwd'], true, 'callback', 'unit-a02'),
    ('INC-0142', 'sos', 'sms', 'enRoute', 'medical', 'medical',
     14.5712, 120.9888, 'Barangay 700', 'Malate', 'Remedios St', null,
     t0 - interval '12 min 30 s', t0 - interval '12 min 26 s', 'res-003', 1, null,
     array['seniorCitizen'], true, 'callback', 'unit-r05'),
    ('INC-0139', 'crowdCluster', 'app', 'onScene', 'structural', 'structural',
     14.61103, 121.00012, 'Barangay 560', 'Sampaloc', null, null,
     t0 - interval '21 min', t0 - interval '18 min 2 s', null, null, null, '{}', false, null, 'unit-r11');

  update public.response_unit set current_incident_id = 'INC-0144' where unit_id = 'unit-a02';
  update public.response_unit set current_incident_id = 'INC-0142' where unit_id = 'unit-r05';
  update public.response_unit set current_incident_id = 'INC-0139' where unit_id = 'unit-r11';

  insert into public.incident_event (incident_id, kind, at, actor_name, detail) values
    ('INC-0147', 'received', t0 - interval '4 min 11 s', null, null),
    ('INC-0149', 'received', t0 - interval '1 min 1 s', null, null),
    ('INC-0146', 'received', t0 - interval '6 min 40 s', null, null),
    ('INC-0144', 'received', t0 - interval '9 min 11 s', null, null),
    ('INC-0144', 'verified', t0 - interval '7 min', dispatcher_name, 'callback'),
    ('INC-0144', 'assigned', t0 - interval '10 s', dispatcher_name, 'A-02'),
    ('INC-0142', 'received', t0 - interval '12 min 26 s', null, null),
    ('INC-0142', 'verified', t0 - interval '10 min', dispatcher_name, 'callback'),
    ('INC-0142', 'assigned', t0 - interval '8 min', dispatcher_name, 'R-05'),
    ('INC-0142', 'enRoute', t0 - interval '7 min', 'R-05', null),
    ('INC-0139', 'received', t0 - interval '18 min 2 s', null, null),
    ('INC-0139', 'assigned', t0 - interval '16 min', dispatcher_name, 'R-11'),
    ('INC-0139', 'onScene', t0 - interval '4 min', 'R-11', null);

  insert into public.dispatch (incident_id, unit_id, dispatch_time, arrival_time) values
    ('INC-0144', 'unit-a02', t0 - interval '10 s', null),
    ('INC-0142', 'unit-r05', t0 - interval '8 min', null),
    ('INC-0139', 'unit-r11', t0 - interval '16 min', t0 - interval '4 min');

  -- Crowd reports: two confirmed clusters and five unverified singles.
  insert into public.crowd_report
    (report_id, description, latitude, longitude, barangay, district, source, submitted_at, category, category_confidence, incident_id)
  values
    ('rep-201', 'Baha na hanggang baywang sa Juan Luna St.', 14.61970, 120.96700, 'Barangay 105', 'Tondo', 'app', t0 - interval '9 min', 'flood', 0.93, 'INC-0146'),
    ('rep-202', 'Flooded street, water entering houses', 14.61985, 120.96715, 'Barangay 105', 'Tondo', 'app', t0 - interval '8 min', 'flood', 0.90, 'INC-0146'),
    ('rep-203', 'Hindi na makalabas, tumataas ang tubig', 14.61958, 120.96722, 'Barangay 105', 'Tondo', 'webForm', t0 - interval '7 min', 'flood', 0.81, 'INC-0146'),
    ('rep-204', 'Mga bata stranded sa second floor', 14.61975, 120.96688, 'Barangay 105', 'Tondo', 'app', t0 - interval '6 min', 'flood', 0.74, 'INC-0146'),
    ('rep-190', 'Wall collapsed onto the alley', 14.61100, 121.00000, 'Barangay 560', 'Sampaloc', 'app', t0 - interval '21 min', 'structural', 0.88, 'INC-0139'),
    ('rep-191', 'Gumuho ang pader, may naipit', 14.61118, 121.00012, 'Barangay 560', 'Sampaloc', 'app', t0 - interval '20 min', 'structural', 0.79, 'INC-0139'),
    ('rep-192', 'Debris blocking the road near the school', 14.61090, 121.00025, 'Barangay 560', 'Sampaloc', 'app', t0 - interval '19 min', 'structural', 0.71, 'INC-0139'),
    ('rep-210', 'Baha na hanggang tuhod sa Dapitan St.', 14.61180, 120.98930, 'Barangay 412', 'Sampaloc', 'app', t0 - interval '3 min', 'flood', 0.91, null),
    ('rep-211', 'Water rising fast near the church, we can''t get the car out', 14.61195, 120.98950, 'Barangay 412', 'Sampaloc', 'webForm', t0 - interval '1 min', 'flood', 0.88, null),
    ('rep-205', 'Smoke from a building on Recto Ave', 14.59900, 120.98400, 'Barangay 306', 'Quiapo', 'app', t0 - interval '12 min', 'fire', 0.84, null),
    ('rep-206', 'Fallen tree blocking the road, no one hurt', 14.57900, 121.00100, 'Barangay 670', 'Paco', 'app', t0 - interval '30 min', 'structural', 0.72, null),
    ('rep-207', 'Tubig sa loob ng bahay, hanggang binti', 14.62550, 120.97150, 'Barangay 128', 'Tondo', 'app', t0 - interval '37 min', 'flood', 0.86, null);

  insert into public.weather_alert (signal_level, rainfall_intensity, storm_surge_advisory, issued_at, is_simulated)
  values (2, 18, 'Storm surge up to 1 m possible along Manila Bay', t0 - interval '2 min', true);

  insert into public.audit_log ("timestamp", account_id, account_name, account_role, action_type, target_table, target_id, detail) values
    (t0 - interval '16 min', dispatcher_id, dispatcher_name, 'dispatcher', 'unitAssigned', 'dispatch', 'INC-0139', 'R-11'),
    (t0 - interval '10 min', dispatcher_id, dispatcher_name, 'dispatcher', 'verified', 'incident_report', 'INC-0142', 'callback'),
    (t0 - interval '8 min', dispatcher_id, dispatcher_name, 'dispatcher', 'unitAssigned', 'dispatch', 'INC-0142', 'R-05'),
    (t0 - interval '7 min', dispatcher_id, dispatcher_name, 'dispatcher', 'verified', 'incident_report', 'INC-0144', 'callback'),
    (t0 - interval '10 s', dispatcher_id, dispatcher_name, 'dispatcher', 'unitAssigned', 'dispatch', 'INC-0144', 'A-02');

  perform setval('public.incident_number_seq', 150, false);
  perform setval('public.crowd_report_number_seq', 300, false);
  perform setval('public.resident_number_seq', 100, false);
  return 'Demo data loaded at ' || to_char(t0 at time zone 'Asia/Manila', 'YYYY-MM-DD HH24:MI:SS') || ' (Manila time)';
end $$;

create or replace function public.demo_new_sos()
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  new_id text;
begin
  insert into public.incident_report (
    origin, channel, status, latitude, longitude, barangay, district, accuracy_m,
    captured_at, received_at, manila_resident_id, vulnerable, account_verified, mock_location
  ) values (
    'sos', 'app', 'pendingVerification', 14.6258, 120.9718, 'Barangay 128', 'Tondo', 5,
    now() - interval '3 seconds', now(), 'res-004', array['pregnant'], true, true
  ) returning incident_id into new_id;
  insert into public.incident_event (incident_id, kind) values (new_id, 'received');
  return new_id;
end $$;

create or replace function public.demo_add_crowd_report()
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  new_id text;
begin
  insert into public.crowd_report
    (description, latitude, longitude, barangay, district, source, category, category_confidence)
  values
    ('Lubog na yung kalsada, may mga bata dito', 14.61170, 120.98955, 'Barangay 412', 'Sampaloc', 'app', 'flood', 0.79)
  returning report_id into new_id;
  return new_id;
end $$;

create or replace function public.demo_advance()
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  r record;
  moved int := 0;
begin
  for r in
    select i.incident_id, i.status, i.latitude, i.longitude, i.assigned_unit_id, u.call_sign
      from public.incident_report i
      join public.response_unit u on u.unit_id = i.assigned_unit_id
     where i.status in ('assigned', 'enRoute', 'onScene')
  loop
    if r.status = 'assigned' then
      update public.response_unit set status = 'enRoute' where unit_id = r.assigned_unit_id;
      update public.incident_report set status = 'enRoute' where incident_id = r.incident_id;
      insert into public.incident_event (incident_id, kind, actor_name) values (r.incident_id, 'enRoute', r.call_sign);
    elsif r.status = 'enRoute' then
      update public.response_unit
         set status = 'onScene', last_latitude = r.latitude, last_longitude = r.longitude, last_location_at = now()
       where unit_id = r.assigned_unit_id;
      update public.incident_report set status = 'onScene' where incident_id = r.incident_id;
      update public.dispatch set arrival_time = now()
       where incident_id = r.incident_id and arrival_time is null;
      insert into public.incident_event (incident_id, kind, actor_name) values (r.incident_id, 'onScene', r.call_sign);
    else
      update public.response_unit set status = 'available', current_incident_id = null
       where unit_id = r.assigned_unit_id;
      update public.incident_report set status = 'resolved', resolved_at = now() where incident_id = r.incident_id;
      update public.dispatch set completion_time = now()
       where incident_id = r.incident_id and completion_time is null;
      insert into public.incident_event (incident_id, kind, actor_name) values (r.incident_id, 'resolved', r.call_sign);
    end if;
    moved := moved + 1;
  end loop;
  return moved || ' incident(s) moved one step';
end $$;

-- Demo and admin tools: SQL editor only.
revoke execute on function
  public.create_staff_account(text, text, text, text, text),
  public.reset_demo_data(), public.demo_new_sos(),
  public.demo_add_crowd_report(), public.demo_advance()
from public, anon, authenticated;
