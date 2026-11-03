-- Surge test (NFR7, 2026-11-03; results in docs/SURGE-TEST.md).
--
-- Thousands of residents send an SOS within an hour, through the real
-- submit_sos(), on the hosted project. Everything runs in ONE transaction
-- that raises an exception at the end, so nothing is kept: no resident,
-- incident, push, SMS, or Facebook post. Run it in the SQL editor (or the
-- connector) as one statement batch.
--
-- Afterwards run surge_restore.sql: the record counters (residents,
-- incidents, crowd reports) are not rolled back by Postgres, and the real
-- next numbers must not jump.
--
-- Change n below (1,000 and 10,000 were run). It needs migration id_width
-- (applied 2026-11-03): before it, the 1,000th resident got 'res-100' and
-- the run stopped.

begin;
set local statement_timeout = '600s';

create temp table __res (i int primary key, auth_id uuid, rid text, brgy text, dist text, lat double precision, lng double precision);
create temp table __lat (i int, ms double precision);
create temp table __out (k text, v text);
do $$
declare
  n int := 10000;            -- residents, one SOS each, spread over the last hour
  t0 timestamptz; t1 timestamptz; rr record; s timestamptz;
begin
  -- Throwaway residents across all 897 barangays; one in seven has a
  -- consented vulnerable household; one in 200 SOS has fake GPS.
  t0 := clock_timestamp();
  insert into __res (i, auth_id, brgy, dist, lat, lng)
  select g, gen_random_uuid(), b.name, b.district, b.center_latitude, b.center_longitude
    from generate_series(1, n) g
    join (select name, district, center_latitude, center_longitude,
                 row_number() over (order by name) - 1 k, count(*) over () c
            from public.barangay) b on b.k = (g * 7919) % b.c;
  insert into auth.users (id) select auth_id from __res;
  insert into public.manila_resident (auth_user_id, fullname, contact_number, barangay, district, consent_given_at)
  select auth_id, 'Surge Test ' || i, '0900' || lpad(i::text, 7, '0'), brgy, dist,
         case when i % 7 = 0 then now() end from __res;
  update __res x set rid = m.manila_resident_id from public.manila_resident m where m.auth_user_id = x.auth_id;
  insert into public.vulnerable_member (manila_resident_id, label, vulnerability_types)
  select rid, 'Household member',
         case i % 3 when 0 then array['seniorCitizen'] when 1 then array['pwd'] else array['pregnant'] end
    from __res where i % 7 = 0;
  insert into __out values ('setup_ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::text);

  -- Each resident sends an SOS, timed one by one.
  t0 := clock_timestamp();
  for rr in select * from __res order by i loop
    perform set_config('request.jwt.claims', json_build_object('sub', rr.auth_id, 'role', 'authenticated')::text, true);
    s := clock_timestamp();
    perform public.submit_sos(gen_random_uuid(), now() - make_interval(secs => (n - rr.i) * 3600.0 / n),
      rr.lat + (random() - 0.5) * 0.002, rr.lng + (random() - 0.5) * 0.002, 12, rr.brgy, rr.dist, rr.i % 200 = 0);
    insert into __lat values (rr.i, extract(epoch from clock_timestamp() - s) * 1000);
  end loop;
  t1 := clock_timestamp();
  insert into __out values ('sos_total_ms', round(extract(epoch from t1 - t0) * 1000)::text);
  insert into __out values ('sos_per_s', round(n / extract(epoch from t1 - t0))::text);
  insert into __out select 'sos_ms_avg_p50_p95_p99_max',
    round(avg(ms)::numeric, 2) || ' / ' || round(percentile_cont(0.5) within group (order by ms)::numeric, 2) || ' / ' ||
    round(percentile_cont(0.95) within group (order by ms)::numeric, 2) || ' / ' ||
    round(percentile_cont(0.99) within group (order by ms)::numeric, 2) || ' / ' || round(max(ms)::numeric, 2) from __lat;
  insert into __out select 'first_vs_last_tenth_avg_ms',
    round(avg(ms) filter (where i <= n / 10)::numeric, 3) || ' vs ' || round(avg(ms) filter (where i > n - n / 10)::numeric, 3) from __lat;
end $$;

-- The dispatcher's board, as the dashboard reads it (incident_board, RLS on).
insert into auth.users (id, email) values ('00000000-0000-4000-8000-0000000000f4', 'surge-disp@test.local');
insert into public.staff (id, display_name, email, role)
  values ('00000000-0000-4000-8000-0000000000f4', 'Surge Disp', 'surge-disp@test.local', 'dispatcher');
grant select, insert on __out to authenticated;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-4000-8000-0000000000f4", "role": "authenticated"}', true);
do $$
declare s timestamptz; c int; i int; bytes bigint; v int;
begin
  for i in 1..3 loop
    s := clock_timestamp();
    select count(*) into c from (select * from public.incident_board where status <> 'resolved' order by received_at) q;
    insert into __out values ('board_query_ms_run' || i, round(extract(epoch from clock_timestamp() - s) * 1000)::text || ' (' || c || ' rows)');
  end loop;
  select sum(length(row_to_json(q)::text)) into bytes from (select * from public.incident_board where status <> 'resolved') q;
  insert into __out values ('board_json_mb', round(bytes / 1048576.0, 1)::text);
  select count(*) into v from public.incident_board where status <> 'resolved' and cardinality(vulnerable) > 0;
  insert into __out select 'vulnerable_in_top_' || v, count(*)::text || ' of ' || v
    from (select vulnerable from public.incident_board where status <> 'resolved' order by priority_score desc limit v) q
   where cardinality(vulnerable) > 0;
  insert into __out select 'fake_gps_best_rank', min(rk)::text
    from (select mock_location, row_number() over (order by priority_score desc) rk from public.incident_board where status <> 'resolved') q
   where mock_location;
end $$;
reset role;

-- One account sends 200 SOS.
do $$
declare a uuid := (select auth_id from __res where i = 1); ok int := 0; k int;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  for k in 1..200 loop
    begin
      perform public.submit_sos(gen_random_uuid(), now(), 14.6, 120.98, 10, null, null, false);
      ok := ok + 1;
    exception when others then null;
    end;
  end loop;
  insert into __out values ('one_account_200_sos_accepted', ok::text);
end $$;

-- The results, and everything above undone.
do $$ declare s text; begin select string_agg(k || '=' || v, ' || ') into s from __out; raise exception 'SURGE: %', s; end $$;
