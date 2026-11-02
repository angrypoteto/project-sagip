-- The typhoon tracker is set aside for now (Joshua, 2026-11-02: "remove the
-- gsmap and the typhoon tracker for now"): the dashboard no longer shows
-- it, so ingest-storms stops running. Its tables (storm_track,
-- pagasa_warning, with their RLS) and save_hazard_feeds() stay, so the
-- tracker can come back by scheduling the job again:
--   select cron.schedule('ingest-storms', '10,40 * * * *',
--     'select private.call_ingest_storms()');

select cron.unschedule('ingest-storms')
  where exists (select 1 from cron.job where jobname = 'ingest-storms');
