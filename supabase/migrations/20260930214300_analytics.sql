-- A4 Performance analytics (plan 7.4, Objective 1).
--
-- analytics_report(from, to) returns, for incidents received in the period:
-- counts, dispatch time (received to the first assignment), verification
-- time (received to verified), response time (received to on scene), travel
-- time (assigned to on scene), SOS by channel, breakdowns by type,
-- barangay, unit, and day (Manila dates), and the Dijkstra timing log. The
-- same definitions as buildAnalytics() in packages/shared (the mock).
--
-- Admins only. Times come from the incident timeline (incident_event), so
-- they are the moments the system recorded, not typed-in values.

create or replace function public.analytics_report(p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  me public.staff;
  result jsonb;
begin
  select * into me from public.staff s where s.id = (select auth.uid());
  if me.id is null or me.role <> 'admin' then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '400 days' then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  with inc as (
    select
      i.incident_id, i.origin, i.channel, i.status, i.false_report,
      coalesce(i.emergency_type, i.suggested_type) as type,
      i.barangay, i.district, i.assigned_unit_id, i.received_at,
      (select min(e.at) from public.incident_event e
        where e.incident_id = i.incident_id and e.kind = 'verified') as verified_at,
      (select min(e.at) from public.incident_event e
        where e.incident_id = i.incident_id and e.kind = 'assigned') as assigned_at,
      (select min(e.at) from public.incident_event e
        where e.incident_id = i.incident_id and e.kind = 'onScene') as on_scene_at
    from public.incident_report i
    where i.received_at >= p_from and i.received_at < p_to
  ),
  t as (
    select inc.*,
      extract(epoch from assigned_at - received_at)::double precision as dispatch_s,
      extract(epoch from verified_at - received_at)::double precision as verify_s,
      extract(epoch from on_scene_at - received_at)::double precision as response_s,
      extract(epoch from on_scene_at - assigned_at)::double precision as travel_s
    from inc
  )
  select jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'incidents', count(*),
    'resolved', count(*) filter (where status = 'resolved'),
    'false_reports', count(*) filter (where false_report),
    'sos', count(*) filter (where origin = 'sos'),
    'clusters', count(*) filter (where origin = 'crowdCluster'),
    'avg_dispatch_s', avg(dispatch_s),
    'median_dispatch_s', percentile_cont(0.5) within group (order by dispatch_s),
    'avg_verify_s', avg(verify_s),
    'avg_response_s', avg(response_s),
    'median_response_s', percentile_cont(0.5) within group (order by response_s),
    'sos_by_channel', coalesce(
      (select jsonb_object_agg(x.channel, x.n)
         from (select t2.channel, count(*) as n from t t2 where t2.origin = 'sos' group by t2.channel) x),
      '{}'::jsonb),
    'by_type', coalesce(
      (select jsonb_agg(jsonb_build_object(
           'key', coalesce(x.type, 'unknown'), 'label', coalesce(x.type, 'unknown'),
           'count', x.n, 'avg_dispatch_s', x.d, 'avg_response_s', x.r)
         order by x.n desc, coalesce(x.type, 'unknown'))
         from (select t2.type, count(*) as n, avg(t2.dispatch_s) as d, avg(t2.response_s) as r
                 from t t2 group by t2.type) x),
      '[]'::jsonb),
    'by_barangay', coalesce(
      (select jsonb_agg(jsonb_build_object(
           'key', x.barangay, 'label', x.barangay || ', ' || x.district,
           'count', x.n, 'avg_dispatch_s', x.d, 'avg_response_s', x.r)
         order by x.n desc, x.barangay)
         from (select t2.barangay, t2.district, count(*) as n, avg(t2.dispatch_s) as d,
                      avg(t2.response_s) as r
                 from t t2 group by t2.barangay, t2.district
                 order by count(*) desc, t2.barangay limit 10) x),
      '[]'::jsonb),
    'by_unit', coalesce(
      (select jsonb_agg(jsonb_build_object(
           'key', x.assigned_unit_id, 'label', coalesce(u.call_sign, x.assigned_unit_id),
           'count', x.n, 'avg_travel_s', x.tr, 'avg_response_s', x.r)
         order by x.n desc, x.assigned_unit_id)
         from (select t2.assigned_unit_id, count(*) as n, avg(t2.travel_s) as tr,
                      avg(t2.response_s) as r
                 from t t2 where t2.assigned_unit_id is not null
                 group by t2.assigned_unit_id) x
         left join public.response_unit u on u.unit_id = x.assigned_unit_id),
      '[]'::jsonb),
    'daily', coalesce(
      (select jsonb_agg(jsonb_build_object('day', x.day, 'count', x.n, 'avg_response_s', x.r)
         order by x.day)
         from (select (t2.received_at at time zone 'Asia/Manila')::date as day, count(*) as n,
                      avg(t2.response_s) as r
                 from t t2 group by 1) x),
      '[]'::jsonb),
    'routing', coalesce(
      (select jsonb_agg(jsonb_build_object(
           'kind', x.kind, 'runs', x.n, 'avg_ms', x.a, 'p95_ms', x.p)
         order by x.kind)
         from (select r.kind, count(*) as n, avg(r.compute_ms)::double precision as a,
                      percentile_cont(0.95) within group (order by r.compute_ms) as p
                 from public.routing_run r
                where r.ran_at >= p_from and r.ran_at < p_to
                group by r.kind) x),
      '[]'::jsonb)
  ) into result
  from t;
  return result;
end $$;

revoke execute on function public.analytics_report(timestamptz, timestamptz) from public, anon;
grant execute on function public.analytics_report(timestamptz, timestamptz) to authenticated;
