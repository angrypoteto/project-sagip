-- Crowd report surge (NFR7 with FR7 clustering, 2026-11-03; results in
-- docs/SURGE-TEST.md). Like surge_test.sql: one transaction that raises at
-- the end, so nothing is kept; then run surge_restore.sql.
--
-- Each crowd report runs the classifier (FR12) and re-clusters every report
-- of the last 60 minutes (DBSCAN, 50 m, 3 reports; FR7), so the cost per
-- report grows as the hour fills. The times are reported per 250 reports.
-- 2,000 reports take about 32 s; 3,000 did not finish within the
-- connector's time limit.

begin;
set local statement_timeout = '600s';

create temp table __res (i int primary key, auth_id uuid, brgy text, dist text, lat double precision, lng double precision);
create temp table __lat (i int, ms double precision, ok boolean, err text);
create temp table __out (k text, v text);
do $$
declare
  n int := 2000;             -- reports, one per resident, spread over the last hour
  t0 timestamptz; rr record; s timestamptz; e text;
begin
  insert into __res (i, auth_id, brgy, dist, lat, lng)
  select g, gen_random_uuid(), b.name, b.district, b.center_latitude, b.center_longitude
    from generate_series(1, n) g
    join (select name, district, center_latitude, center_longitude,
                 row_number() over (order by name) - 1 k, count(*) over () c
            from public.barangay) b on b.k = (g * 7919) % b.c;
  insert into auth.users (id) select auth_id from __res;
  insert into public.manila_resident (auth_user_id, fullname, contact_number, barangay, district)
  select auth_id, 'Surge Test ' || i, '0900' || lpad(i::text, 7, '0'), brgy, dist from __res;
  t0 := clock_timestamp();
  for rr in select * from __res order by i loop
    perform set_config('request.jwt.claims', json_build_object('sub', rr.auth_id, 'role', 'authenticated')::text, true);
    e := null;
    s := clock_timestamp();
    begin
      perform public.submit_crowd_report(gen_random_uuid(), now() - make_interval(secs => (n - rr.i) * 3500.0 / n),
        'Baha na po dito hanggang tuhod', null,
        rr.lat + (random() - 0.5) * 0.0008, rr.lng + (random() - 0.5) * 0.0008, 15, null, null, 'app');
    exception when others then e := sqlerrm;
    end;
    insert into __lat values (rr.i, extract(epoch from clock_timestamp() - s) * 1000, e is null, e);
  end loop;
  insert into __out values ('reports_total_ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::text);
  insert into __out select 'avg_ms_by_250', string_agg(((b - 1) * 250 + 1) || '-' || (b * 250) || ':' || round(a::numeric, 1), ', ' order by b)
    from (select (i - 1) / 250 + 1 b, avg(ms) a from __lat where ok group by 1) q;
  insert into __out select 'refused', count(*)::text || ' ' || coalesce(string_agg(distinct err, ','), '') from __lat where not ok;
  insert into __out select 'cluster_incidents', count(*)::text from public.incident_report where origin = 'crowdCluster' and status <> 'resolved';
end $$;

-- One account sends 20 reports: the hourly limit (A3, 5) stops it.
do $$
declare a uuid := (select auth_id from __res where i = 1); ok int := 0; k int; last_err text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  for k in 1..20 loop
    begin
      perform public.submit_crowd_report(gen_random_uuid(), now(), 'Baha dito', null, 14.6, 120.98, 10, null, null, 'app');
      ok := ok + 1;
    exception when others then last_err := sqlerrm;
    end;
  end loop;
  insert into __out values ('one_account_20_more_accepted', ok::text || ' (refusal: ' || coalesce(last_err, 'none') || ')');
end $$;

do $$ declare s text; begin select string_agg(k || '=' || v, ' || ') into s from __out; raise exception 'SURGE REPORTS: %', s; end $$;
