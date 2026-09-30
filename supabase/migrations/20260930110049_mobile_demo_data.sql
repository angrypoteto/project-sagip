-- Demo data for the mobile app: past rescues (R6, F7), sample alerts (R7),
-- and sample forecasts. Replaces reset_demo_data(); everything else about it
-- is unchanged (see 20260930000311_demo_data.sql). Applying this migration
-- does not reload the data; run this in the SQL editor when ready (it
-- replaces the demo data):
--
--   select public.reset_demo_data();
--
-- All names and numbers are fictional.

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
  -- Clear domain data. Staff accounts and barangays are kept.
  update public.response_unit set current_incident_id = null;
  delete from public.completion_report;
  delete from public.alert_read;
  delete from public.public_alert;
  delete from public.barangay_forecast;
  delete from public.data_deletion_request;
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

  -- Reports keep the phone's capture time; for the samples it is the send time.
  update public.crowd_report set captured_at = submitted_at;

  -- Past rescues: history for R-03 (F7) and Maria (R6). All resolved, so
  -- they stay off the Triage Queue.
  insert into public.incident_report (
    incident_id, origin, channel, status, suggested_type, emergency_type,
    latitude, longitude, barangay, district, address, accuracy_m,
    captured_at, received_at, manila_resident_id, people_count, vulnerable,
    account_verified, verification_method, assigned_unit_id, resolved_at,
    real_emergency, people_found
  ) values
    ('INC-0118', 'sos', 'app', 'resolved', 'flood', 'flood',
     14.6091, 120.9925, 'Barangay 412', 'Sampaloc', '1482 Dapitan St', 9,
     t0 - interval '12 days 3 hours', t0 - interval '12 days 3 hours' + interval '2 s', 'res-001', 3,
     array['pwd', 'seniorCitizen'], true, 'callback', 'unit-r03', t0 - interval '12 days 2 hours 10 min',
     true, 3),
    ('INC-0124', 'crowdCluster', 'app', 'resolved', 'flood', 'flood',
     14.61103, 121.00012, 'Barangay 560', 'Sampaloc', null, null,
     t0 - interval '8 days 1 hour', t0 - interval '8 days 55 min', null, null, '{}',
     false, 'onScene', 'unit-r03', t0 - interval '8 days 10 min', true, 2),
    ('INC-0131', 'sos', 'sms', 'resolved', 'medical', 'medical',
     14.6123, 120.9968, 'Barangay 490', 'Sampaloc', '930 Maria Clara St', null,
     t0 - interval '4 days 2 hours', t0 - interval '4 days 2 hours' + interval '4 s', null, 1,
     array['seniorCitizen'], true, 'callback', 'unit-r03', t0 - interval '4 days 1 hour 20 min', true, 1),
    ('INC-0141', 'crowdCluster', 'app', 'resolved', 'flood', 'flood',
     14.6112, 120.9901, 'Barangay 412', 'Sampaloc', 'Dapitan St', null,
     t0 - interval '3 days 30 min', t0 - interval '3 days 25 min', null, null, '{}',
     false, 'onScene', 'unit-r07', t0 - interval '2 days 23 hours', true, 0);

  insert into public.incident_event (incident_id, kind, at, actor_name, detail) values
    ('INC-0118', 'received', t0 - interval '12 days 3 hours', null, null),
    ('INC-0118', 'verified', t0 - interval '12 days 2 hours 57 min', dispatcher_name, 'callback'),
    ('INC-0118', 'assigned', t0 - interval '12 days 2 hours 55 min', dispatcher_name, 'R-03'),
    ('INC-0118', 'enRoute', t0 - interval '12 days 2 hours 54 min', 'R-03', null),
    ('INC-0118', 'onScene', t0 - interval '12 days 2 hours 41 min', 'R-03', null),
    ('INC-0118', 'resolved', t0 - interval '12 days 2 hours 10 min', 'R-03', 'rescued'),
    ('INC-0124', 'received', t0 - interval '8 days 55 min', null, null),
    ('INC-0124', 'assigned', t0 - interval '8 days 50 min', dispatcher_name, 'R-03'),
    ('INC-0124', 'enRoute', t0 - interval '8 days 49 min', 'R-03', null),
    ('INC-0124', 'onScene', t0 - interval '8 days 38 min', 'R-03', null),
    ('INC-0124', 'verified', t0 - interval '8 days 37 min', 'R-03', 'onScene'),
    ('INC-0124', 'resolved', t0 - interval '8 days 10 min', 'R-03', 'rescued'),
    ('INC-0131', 'received', t0 - interval '4 days 2 hours', null, null),
    ('INC-0131', 'verified', t0 - interval '4 days 1 hour 58 min', dispatcher_name, 'callback'),
    ('INC-0131', 'assigned', t0 - interval '4 days 1 hour 57 min', dispatcher_name, 'R-03'),
    ('INC-0131', 'enRoute', t0 - interval '4 days 1 hour 56 min', 'R-03', null),
    ('INC-0131', 'onScene', t0 - interval '4 days 1 hour 45 min', 'R-03', null),
    ('INC-0131', 'resolved', t0 - interval '4 days 1 hour 20 min', 'R-03', 'transported'),
    ('INC-0141', 'received', t0 - interval '3 days 25 min', null, null),
    ('INC-0141', 'assigned', t0 - interval '3 days 20 min', dispatcher_name, 'R-07'),
    ('INC-0141', 'enRoute', t0 - interval '3 days 19 min', 'R-07', null),
    ('INC-0141', 'onScene', t0 - interval '3 days 8 min', 'R-07', null),
    ('INC-0141', 'verified', t0 - interval '3 days 7 min', 'R-07', 'onScene'),
    ('INC-0141', 'resolved', t0 - interval '2 days 23 hours', 'R-07', 'rescued');

  insert into public.dispatch (incident_id, unit_id, dispatch_time, arrival_time, completion_time) values
    ('INC-0118', 'unit-r03', t0 - interval '12 days 2 hours 55 min', t0 - interval '12 days 2 hours 41 min', t0 - interval '12 days 2 hours 10 min'),
    ('INC-0124', 'unit-r03', t0 - interval '8 days 50 min', t0 - interval '8 days 38 min', t0 - interval '8 days 10 min'),
    ('INC-0131', 'unit-r03', t0 - interval '4 days 1 hour 57 min', t0 - interval '4 days 1 hour 45 min', t0 - interval '4 days 1 hour 20 min'),
    ('INC-0141', 'unit-r07', t0 - interval '3 days 20 min', t0 - interval '3 days 8 min', t0 - interval '2 days 23 hours');

  insert into public.completion_report (
    report_id, incident_id, unit_id, captured_at, outcome, persons_assisted,
    time_on_scene_s, houses_damaged, injured, missing, affected_families, notes
  ) values
    (gen_random_uuid(), 'INC-0118', 'unit-r03', t0 - interval '12 days 2 hours 10 min', 'rescued', 3, 1860, 1, 0, 0, 1, 'Moved the family and Lolo Andres to the barangay hall.'),
    (gen_random_uuid(), 'INC-0124', 'unit-r03', t0 - interval '8 days 10 min', 'rescued', 2, 1680, 0, 0, 0, 2, null),
    (gen_random_uuid(), 'INC-0131', 'unit-r03', t0 - interval '4 days 1 hour 20 min', 'transported', 1, 1500, 0, 1, 0, 1, 'Taken to the district hospital.'),
    (gen_random_uuid(), 'INC-0141', 'unit-r07', t0 - interval '2 days 23 hours', 'rescued', 0, 3900, 4, 0, 0, 6, 'Street flooding; no one needed rescue by the time we arrived.');

  -- Maria's past reports: one joined a confirmed incident, one no one else made.
  insert into public.crowd_report
    (report_id, manila_resident_id, description, latitude, longitude, barangay, district, source,
     submitted_at, captured_at, reported_type, incident_id)
  values
    ('rep-190001', 'res-001', 'Knee-deep flood on Dapitan St near the market', 14.61120, 120.99010,
     'Barangay 412', 'Sampaloc', 'app', t0 - interval '3 days 30 min', t0 - interval '3 days 30 min', 'flood', 'INC-0141'),
    ('rep-190002', 'res-001', 'Smell of smoke near España Blvd', 14.61030, 120.98900,
     'Barangay 412', 'Sampaloc', 'app', t0 - interval '20 days', t0 - interval '20 days', 'fire', null);

  -- Sample alerts (R7). Fictional text in the style of real advisories.
  insert into public.public_alert (alert_id, source, level, title, body, guidance, barangays, issued_at, is_simulated) values
    ('alert-mdrrmd-1', 'mdrrmd', 'warning', 'Flooding on Dapitan St and España Blvd',
     'Rescue teams are responding to knee-deep flooding along Dapitan St. Avoid the area if you can. If you need rescue, hold the SOS button in the app.',
     array['Do not walk or drive through floodwater.', 'Keep your phone charged in case you need to send an SOS.'],
     array['Barangay 412', 'Barangay 490'], t0 - interval '25 min', true),
    ('alert-pagasa-rain', 'pagasa', 'warning', 'Orange rainfall warning for Metro Manila',
     'Heavy rain of 15 to 30 mm per hour is falling and may continue for the next 3 hours. Flooding is threatening low-lying areas.',
     array['Move appliances and important papers to a higher place.', 'Avoid wading in floodwater; it can carry disease and live wires.', 'Prepare a go-bag with water, food, medicine, and a flashlight.'],
     '{}', t0 - interval '50 min', true),
    ('alert-pagasa-tc', 'pagasa', 'warning', 'Wind Signal No. 2 raised over Metro Manila',
     'A severe tropical storm may bring gale-force winds of 62 to 88 km per hour within 24 hours. Light structures and trees may be damaged.',
     array['Secure or bring in loose objects outside your home.', 'Stay indoors unless MDRRMD tells you to leave.'],
     '{}', t0 - interval '3 hours', true),
    ('alert-phivolcs-1', 'phivolcs', 'info', 'Taal Volcano advisory: possible light ashfall',
     'PHIVOLCS reports steam and gas emission from Taal Volcano. Light ashfall may reach parts of Metro Manila depending on the wind.',
     array['If ash falls, wear a face mask or a damp cloth over your nose and mouth.', 'Keep windows and doors closed.'],
     '{}', t0 - interval '1 day 2 hours', true);

  -- Sample 72-hour forecasts, issued at 6 AM Manila time (the daily run).
  -- Barangay 306 and 461 have none, to show the empty state.
  insert into public.barangay_forecast
    (barangay, district, issued_at, valid_until, flood_risk, fire_risk, surge_risk, model_version, is_simulated)
  select f.barangay, f.district, run.at, run.at + interval '72 hours', f.flood, f.fire, f.surge, 'sample', true
    from (values
      ('Barangay 105', 'Tondo', 'moderate', 'high', 'moderate'),
      ('Barangay 128', 'Tondo', 'moderate', 'moderate', 'low'),
      ('Barangay 287', 'Binondo', 'moderate', 'moderate', 'low'),
      ('Barangay 412', 'Sampaloc', 'high', 'low', 'low'),
      ('Barangay 490', 'Sampaloc', 'high', 'low', 'low'),
      ('Barangay 560', 'Sampaloc', 'high', 'low', 'low'),
      ('Barangay 649', 'Port Area', 'moderate', 'low', 'high'),
      ('Barangay 700', 'Malate', 'moderate', 'low', 'high')
    ) as f(barangay, district, flood, fire, surge),
    lateral (
      select case when d.today6 > t0 then d.today6 - interval '1 day' else d.today6 end as at
        from (select (date_trunc('day', t0 at time zone 'Asia/Manila') + interval '6 hours')
                       at time zone 'Asia/Manila' as today6) d
    ) run;

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

revoke execute on function public.reset_demo_data() from public, anon, authenticated;
