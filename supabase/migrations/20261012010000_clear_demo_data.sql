-- Empties the hosted project of everything that was made up for demos
-- (Joshua, 2026-10-12): the sample incidents and their records, the sample
-- residents and households, the sample rescue units, the sample forecast
-- run, the classifier trained on invented reports, and the texts, pushes,
-- and reports made from them.
--
-- Kept: staff accounts (but not the temporary emulator account), the 897
-- barangays and the city outline, the settings, what the live feeds read
-- (PHIVOLCS earthquakes, river levels, feed health), the Dijkstra timing
-- log (real measurements, whatever incident they were taken on), and the
-- reference passages of the report's language model step (guidance on
-- wording, not records; they are marked provisional). PDFs of final
-- reports already kept in storage stay there: the bucket allows no
-- deleting, so remove them in the dashboard's Storage page if any exist.
--
-- clear_demo_data() is run once, by hand, in the SQL editor:
--   select public.clear_demo_data();
-- No app can call it. After it: the Command Board is empty until a real or
-- a simulated SOS arrives, nothing can be dispatched until MDRRMD's real
-- units are entered on A2 Resources, reports are not tagged with a type
-- until the classifier trained on real descriptions is loaded, and D8 says
-- there is no forecast.
--
-- reset_demo_data() stays for the RLS test, which loads the sample data
-- inside a transaction that is rolled back. Do not run it by hand any more:
-- it would put the made-up records back.

create function public.clear_demo_data()
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  n_incidents int;
  n_reports int;
  n_residents int;
  n_units int;
  n_forecasts int;
  n_models int;
begin
  select count(*) into n_incidents from public.incident_report;
  select count(*) into n_reports from public.crowd_report;
  select count(*) into n_residents from public.manila_resident;
  select count(*) into n_units from public.response_unit;
  select count(*) into n_forecasts from public.barangay_forecast;
  select count(*) into n_models from public.classifier_model;

  -- Incidents and everything that hangs on them.
  update public.response_unit set current_incident_id = null;
  delete from public.completion_report;
  delete from public.rescue_confirmation;
  delete from public.sms_check;
  delete from public.push_message;
  delete from public.sos_relay_log;
  delete from public.dispatch;
  delete from public.incident_event;
  delete from public.crowd_report;
  delete from public.incident_report;

  -- Alerts, weather readings (the feed records the next real one), and
  -- the sample forecast.
  delete from public.alert_read;
  delete from public.alert_delivery;
  delete from public.public_alert;
  delete from public.weather_alert;
  delete from public.barangay_forecast;

  -- Sample residents and their households.
  delete from public.data_deletion_request;
  delete from public.vulnerable_member;
  delete from public.manila_resident;

  -- Sample units.
  update public.staff set unit_id = null;
  delete from public.response_unit;

  -- The classifier trained on invented reports: new reports stay untagged
  -- until the real model is loaded.
  delete from public.classifier_model;

  -- Reports drafted from the sample figures, the texts and pushes of the
  -- demos, phones registered for them, and the trail of demo actions.
  delete from public.ndrrmc_report;
  delete from public.report_rewrite;
  delete from public.sms_log;
  delete from public.push_device;
  delete from public.audit_log;

  -- The temporary account made for the emulator checks.
  delete from public.staff where email = 'tmp-emulator@sagip.test';
  delete from auth.users where email = 'tmp-emulator@sagip.test';

  return jsonb_build_object(
    'incidents', n_incidents, 'crowd_reports', n_reports, 'residents', n_residents,
    'units', n_units, 'forecast_rows', n_forecasts, 'classifier_models', n_models);
end $$;

revoke all on function public.clear_demo_data() from public, anon, authenticated;
