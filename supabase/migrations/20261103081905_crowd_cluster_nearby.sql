-- Surge test finding 3 (NFR7, docs/SURGE-TEST.md; Joshua, 2026-11-03: "fix
-- it"). Every new crowd report re-ran DBSCAN over all reports of the last
-- 60 minutes and walked every cluster again, so a report cost 11 ms at the
-- start of a busy hour and 27 ms after 2,000. Two reports arriving at the
-- same instant could also each create an incident for the same new cluster.
--
-- Now:
-- 1. Only reports within about 150 m of the new ones (three times DBSCAN's
--    50 m) are clustered again, found through an index on position. A new
--    report joins or forms a cluster only through reports within 100 m of
--    it (a neighbour within 50 m, and that neighbour's own neighbours);
--    reports farther away already have the incident they belong to and
--    keep it. The thesis parameters (metres in UTM 51N, eps 50 m, minPts 3,
--    the last 60 minutes) are unchanged.
-- 2. Only the clusters that hold a new report or a report without an
--    incident yet are looked at; the others cannot change. (A report
--    between two clusters can land in either, depending on the order the
--    rows are read, so the second condition matters.) Before, every
--    cluster in the window was walked on every report.
-- 3. Re-clustering takes a transaction lock, so simultaneous reports are
--    clustered one after the other and never make two incidents for one
--    cluster.
-- The trigger now passes the inserted rows (a transition table).
-- Checked in rolled-back runs on the hosted project: on 800 seeded reports
-- (10 hotspots) the same clusters, members, and incidents as the old
-- function run at the same time (6 incidents, 203 reports, identical
-- positions); on 3,000 dense reports 10.8 ms per report at the start of the
-- hour and 13.6 ms at the end (old: 27 ms by 2,000; without any clustering
-- a flat 10.8 ms).

create index if not exists crowd_report_position_idx
  on public.crowd_report (latitude, longitude);

create or replace function public.recluster_crowd_reports()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c record;
  new_id text;
  lat_lo double precision;
  lat_hi double precision;
  lng_lo double precision;
  lng_hi double precision;
begin
  -- One re-cluster at a time (2026-11-03).
  perform pg_advisory_xact_lock(hashtext('sagip.recluster_crowd_reports'));
  -- 150 m around the new reports: 0.00135 degrees of latitude, 0.0014 of
  -- longitude at Manila's latitude.
  select min(f.latitude) - 0.00135, max(f.latitude) + 0.00135,
         min(f.longitude) - 0.0014, max(f.longitude) + 0.0014
    into lat_lo, lat_hi, lng_lo, lng_hi
    from new_rows f
   where f.captured_at > now() - interval '60 minutes'
     and f.latitude is not null and f.longitude is not null;
  if lat_lo is null then
    return null;
  end if;
  for c in
    with fresh as (
      select f.report_id, f.latitude, f.longitude
        from new_rows f
       where f.captured_at > now() - interval '60 minutes'
         and f.latitude is not null and f.longitude is not null
    ), recent as (
      select r.report_id, r.incident_id, coalesce(r.category, r.reported_type) as category,
             r.latitude, r.longitude, r.barangay, r.district, r.source, r.captured_at,
             extensions.st_clusterdbscan(
               extensions.st_transform(
                 extensions.st_setsrid(extensions.st_makepoint(r.longitude, r.latitude), 4326),
                 32651
               ),
               50, 3
             ) over () as cluster_id,
             r.report_id in (select f.report_id from fresh f) as is_new
        from public.crowd_report r
       where r.latitude between lat_lo and lat_hi
         and r.longitude between lng_lo and lng_hi
         and r.captured_at > now() - interval '60 minutes'
         and exists (select 1 from fresh f
                      where abs(r.latitude - f.latitude) < 0.00135
                        and abs(r.longitude - f.longitude) < 0.0014)
    )
    select cluster_id,
           array_agg(report_id order by captured_at) as report_ids,
           (array_agg(incident_id order by captured_at) filter (where incident_id is not null))[1] as incident_id,
           mode() within group (order by category) filter (where category is not null) as category,
           avg(latitude) as latitude,
           avg(longitude) as longitude,
           min(captured_at) as first_at,
           (array_agg(barangay order by captured_at))[1] as barangay,
           (array_agg(district order by captured_at))[1] as district,
           (array_agg(source order by captured_at))[1] as source
      from recent
     where cluster_id is not null
     group by cluster_id
    having bool_or(is_new) or bool_or(incident_id is null)
  loop
    if c.incident_id is null then
      insert into public.incident_report (
        origin, channel, status, suggested_type, latitude, longitude,
        barangay, district, captured_at, received_at
      ) values (
        'crowdCluster', c.source, 'confirmed', c.category, c.latitude, c.longitude,
        c.barangay, c.district, c.first_at, now()
      ) returning incident_id into new_id;
      insert into public.incident_event (incident_id, kind) values (new_id, 'received');
      update public.crowd_report set incident_id = new_id where report_id = any (c.report_ids);
    else
      update public.crowd_report set incident_id = c.incident_id
       where report_id = any (c.report_ids) and incident_id is null;
    end if;
  end loop;
  return null;
end $$;

revoke execute on function public.recluster_crowd_reports() from public, anon, authenticated;

drop trigger crowd_report_cluster on public.crowd_report;
create trigger crowd_report_cluster
  after insert on public.crowd_report
  referencing new table as new_rows
  for each statement execute function public.recluster_crowd_reports();
