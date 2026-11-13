-- Simulated crowd reports must never reach the MDRRMD Facebook Page
-- (2026-11-14). On 2026-11-12 two simulated fire clusters (INC-0238,
-- INC-0239) were posted as "Confirmed fire in Pandacan": the cluster
-- incident was inserted with is_simulated false, queue_incident_post saw a
-- real confirmed fire and queued the post, and only afterwards did the
-- crowd_report trigger mark the incident simulated. The incident is now
-- created simulated when every report in its cluster is simulated, so the
-- post is held back from the start ('simulated'). Real reports are unchanged.

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
             r.is_simulated,
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
           (array_agg(source order by captured_at))[1] as source,
           bool_and(is_simulated) as is_simulated
      from recent
     where cluster_id is not null
     group by cluster_id
    having bool_or(is_new) or bool_or(incident_id is null)
  loop
    if c.incident_id is null then
      insert into public.incident_report (
        origin, channel, status, suggested_type, latitude, longitude,
        barangay, district, captured_at, received_at, is_simulated
      ) values (
        'crowdCluster', c.source, 'confirmed', c.category, c.latitude, c.longitude,
        c.barangay, c.district, c.first_at, now(), c.is_simulated
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
