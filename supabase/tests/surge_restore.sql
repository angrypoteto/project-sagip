-- After a surge test (surge_test.sql, surge_reports_test.sql): Postgres
-- does not roll back sequences, so the test moved the next resident,
-- incident, and crowd report numbers on. Put them back to the highest
-- number in use, so the next real record is numbered right after it.
-- Run it after every surge run, and only when no real record arrived
-- during the run.

select setval('public.resident_number_seq',
  coalesce((select max(substring(manila_resident_id from 5)::bigint) from public.manila_resident
             where manila_resident_id ~ '^res-[0-9]+$'), 1));
select setval('public.incident_number_seq',
  coalesce((select max(substring(incident_id from 5)::bigint) from public.incident_report
             where incident_id ~ '^INC-[0-9]+$'), 1));
select setval('public.crowd_report_number_seq',
  coalesce((select max(substring(report_id from 5)::bigint) from public.crowd_report
             where report_id ~ '^rep-[0-9]+$'), 1));
