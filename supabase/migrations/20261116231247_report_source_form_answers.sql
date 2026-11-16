-- The MDRRMD report counts the answers of MDRRMD's own forms (Joshua,
-- 2026-11-17: the crew's report asks the EMR, flood and fire forms'
-- questions, and MDRRMD validates it). report_source() gains 'form':
-- counts by fire type, EMR type, cause of road accident, vehicles, flood
-- cause, level and status, patients by age bracket, gender and receiving
-- hospital, and the totals of estimated fire damage (pesos) and affected
-- individuals. Only validated crew reports count, as before; patients'
-- names are never read.

create or replace function public.report_source(p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  result jsonb;
begin
  perform private.require_admin();
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '400 days' then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  with inc as (
    select
      i.incident_id, i.origin, i.status, i.false_report, i.vulnerable,
      coalesce(i.emergency_type, i.suggested_type) as type,
      i.barangay, i.district, i.received_at,
      (select min(e.at) from public.incident_event e
        where e.incident_id = i.incident_id and e.kind = 'assigned') as assigned_at,
      (select min(e.at) from public.incident_event e
        where e.incident_id = i.incident_id and e.kind = 'onScene') as on_scene_at,
      (select min(e.at) from public.incident_event e
        where e.incident_id = i.incident_id and e.kind = 'verified') as verified_at
    from public.incident_report i
    where i.received_at >= p_from and i.received_at < p_to and not i.is_simulated
  ),
  -- Only what MDRRMD validated counts.
  comp as (
    select c.outcome, c.persons_assisted, c.injured, c.missing, c.affected_families, c.houses_damaged,
           c.details
      from public.completion_report c
      join inc on inc.incident_id = c.incident_id
     where c.validated_at is not null
  ),
  -- The patients on validated EMR reports, without names (2026-11-17).
  pat as (
    select p
      from comp,
           jsonb_array_elements(case when jsonb_typeof(comp.details -> 'patients') = 'array'
                                     then comp.details -> 'patients' else '[]'::jsonb end) p
  ),
  -- Each fire's newest time per stage.
  stages as (
    select e.incident_id, e.detail as stage, max(e.at) as at
      from public.incident_event e
      join inc on inc.incident_id = e.incident_id and inc.type = 'fire'
     where e.kind = 'fireStage'
     group by e.incident_id, e.detail
  ),
  highest as (
    select distinct on (s.incident_id) s.incident_id, s.stage
      from stages s
     where array_position(private.fire_stages(), s.stage) <= array_position(private.fire_stages(), 'generalAlarm')
     order by s.incident_id, array_position(private.fire_stages(), s.stage) desc
  ),
  disp as (
    select d.unit_id from public.dispatch d join inc on inc.incident_id = d.incident_id
  ),
  alerts as (
    select a.is_simulated from public.public_alert a
     where a.issued_at >= p_from and a.issued_at < p_to
  ),
  weather as (
    select w.signal_level, w.rainfall_intensity, w.storm_surge_m, w.is_simulated
      from public.weather_alert w
     where w.issued_at >= p_from and w.issued_at < p_to
  )
  select jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'incidents', (select count(*) from inc),
    'sos', (select count(*) from inc where origin = 'sos'),
    'clusters', (select count(*) from inc where origin = 'crowdCluster'),
    'resolved', (select count(*) from inc where status = 'resolved' and not false_report),
    'open', (select count(*) from inc where status <> 'resolved'),
    'false_reports', (select count(*) from inc where false_report),
    'vulnerable_incidents', (select count(*) from inc where cardinality(vulnerable) > 0),
    'by_type', coalesce(
      (select jsonb_agg(jsonb_build_object('type', x.type, 'count', x.n)
                order by x.n desc, x.type nulls last)
         from (select type, count(*) as n from inc group by type) x),
      '[]'::jsonb),
    'by_barangay', coalesce(
      (select jsonb_agg(jsonb_build_object('barangay', x.barangay, 'district', x.district, 'count', x.n)
                order by x.n desc, x.barangay)
         from (select barangay, min(district) as district, count(*) as n from inc group by barangay) x),
      '[]'::jsonb),
    'completion_reports', (select count(*) from comp),
    'reports_awaiting_validation', (
      select count(*) from public.completion_report c
        join inc on inc.incident_id = c.incident_id
       where c.validated_at is null),
    'resolved_without_report', (
      select count(*) from inc
       where inc.status = 'resolved' and not inc.false_report
         and not exists (select 1 from public.completion_report c where c.incident_id = inc.incident_id)),
    'persons_assisted', (select coalesce(sum(persons_assisted), 0) from comp),
    'injured', (select coalesce(sum(injured), 0) from comp),
    'missing', (select coalesce(sum(missing), 0) from comp),
    'affected_families', (select coalesce(sum(affected_families), 0) from comp),
    'houses_damaged', (select coalesce(sum(houses_damaged), 0) from comp),
    'outcomes', coalesce(
      (select jsonb_object_agg(x.outcome, x.n)
         from (select outcome, count(*) as n from comp group by outcome) x),
      '{}'::jsonb),
    'fires_by_highest_alarm', coalesce(
      (select jsonb_object_agg(x.stage, x.n)
         from (select stage, count(*) as n from highest group by stage) x),
      '{}'::jsonb),
    -- The answers of MDRRMD's forms on validated crew reports, as counts
    -- (2026-11-17). No names.
    'form', jsonb_build_object(
      'fire_kind', (select coalesce(jsonb_object_agg(x.k, x.n), '{}'::jsonb)
                  from (select comp.details ->> 'fire_kind' as k, count(*) as n from comp
                         where comp.details ? 'fire_kind' group by 1) x),
      'emr_type', (select coalesce(jsonb_object_agg(x.k, x.n), '{}'::jsonb)
                  from (select comp.details ->> 'emr_type' as k, count(*) as n from comp
                         where comp.details ? 'emr_type' group by 1) x),
      'accident_cause', (select coalesce(jsonb_object_agg(x.k, x.n), '{}'::jsonb)
                  from (select comp.details ->> 'accident_cause' as k, count(*) as n from comp
                         where comp.details ? 'accident_cause' group by 1) x),
      'flood_cause', (select coalesce(jsonb_object_agg(x.k, x.n), '{}'::jsonb)
                  from (select comp.details ->> 'flood_cause' as k, count(*) as n from comp
                         where comp.details ? 'flood_cause' group by 1) x),
      'flood_level', (select coalesce(jsonb_object_agg(x.k, x.n), '{}'::jsonb)
                  from (select comp.details ->> 'flood_level' as k, count(*) as n from comp
                         where comp.details ? 'flood_level' group by 1) x),
      'flood_status', (select coalesce(jsonb_object_agg(x.k, x.n), '{}'::jsonb)
                  from (select comp.details ->> 'flood_status' as k, count(*) as n from comp
                         where comp.details ? 'flood_status' group by 1) x),
      'vehicles', (select coalesce(jsonb_object_agg(x.k, x.n), '{}'::jsonb)
                  from (select v as k, count(*) as n from comp,
                               jsonb_array_elements_text(case when jsonb_typeof(comp.details -> 'vehicles') = 'array'
                                                              then comp.details -> 'vehicles' else '[]'::jsonb end) v
                         group by 1) x),
      'patient_age', (select coalesce(jsonb_object_agg(x.k, x.n), '{}'::jsonb)
                  from (select pat.p ->> 'age' as k, count(*) as n from pat
                         where pat.p ? 'age' group by 1) x),
      'patient_gender', (select coalesce(jsonb_object_agg(x.k, x.n), '{}'::jsonb)
                  from (select pat.p ->> 'gender' as k, count(*) as n from pat
                         where pat.p ? 'gender' group by 1) x),
      'patient_hospital', (select coalesce(jsonb_object_agg(x.k, x.n), '{}'::jsonb)
                  from (select pat.p ->> 'hospital' as k, count(*) as n from pat
                         where pat.p ? 'hospital' group by 1) x),
      'patients', (select count(*) from pat),
      'fire_damage_php', (select coalesce(sum((comp.details ->> 'estimated_damage')::bigint), 0) from comp
                           where jsonb_typeof(comp.details -> 'estimated_damage') = 'number'),
      'fire_affected_individuals', (select coalesce(sum((comp.details ->> 'affected_individuals')::bigint), 0) from comp
                                     where jsonb_typeof(comp.details -> 'affected_individuals') = 'number')
    ),
    'median_fire_out_s', (
      select percentile_cont(0.5) within group (
               order by extract(epoch from s.at - inc.verified_at)::double precision)
        from stages s join inc on inc.incident_id = s.incident_id
       where s.stage = 'fireOut' and inc.verified_at is not null and s.at >= inc.verified_at),
    'dispatches', (select count(*) from disp),
    'units_deployed', (select count(distinct unit_id) from disp),
    'median_dispatch_s', (
      select percentile_cont(0.5) within group (
               order by extract(epoch from assigned_at - received_at)::double precision)
        from inc),
    'median_response_s', (
      select percentile_cont(0.5) within group (
               order by extract(epoch from on_scene_at - received_at)::double precision)
        from inc),
    'alerts_issued', (select count(*) from alerts),
    'alerts_simulated', (select count(*) from alerts where is_simulated),
    'max_signal', (select max(signal_level) from weather),
    'max_rainfall', (select max(rainfall_intensity) from weather),
    'max_surge_m', (select max(storm_surge_m) from weather),
    'weather_simulated', (select coalesce(bool_or(is_simulated), false) from weather)
  ) into result;
  return result;
end $$;
