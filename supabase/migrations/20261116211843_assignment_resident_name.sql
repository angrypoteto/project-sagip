-- The crew's report starts filled in (Joshua, 2026-11-17: "make some of the
-- information already have details since we already have some details
-- about the incidents and the name of the person"; asked whether the name
-- goes to the responder's phone or is filled in on the dashboard: "do the
-- send the name to the responder").
--
-- my_assignments() now also gives the assigned crew:
--   resident_name: the full name of the resident who sent the SOS, for the
--     first patient on the EMR report. Only for an SOS (a crowd cluster has
--     no single sender) and not once the incident is anonymized. This
--     changes plan Q9 (the phone had vulnerability types only): the name
--     goes to the unit assigned to that SOS only, for as long as the job is
--     open, as the SOS already shows it to dispatchers.
--   highest_alarm: the highest fire alarm the dispatcher recorded (a
--     fireStage event between 1st alarm and General alarm), for the fire
--     report's "Highest alarm level".

create or replace function public.my_assignments()
returns jsonb
language sql
stable security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'incident_id', i.incident_id,
      'offered_at', coalesce(
        (select max(e.at) from public.incident_event e
          where e.incident_id = i.incident_id and e.kind = 'assigned'),
        i.received_at),
      'latitude', i.latitude,
      'longitude', i.longitude,
      'barangay', i.barangay,
      'district', i.district,
      'address', i.address,
      'channel', i.channel,
      'type', coalesce(i.emergency_type, i.suggested_type),
      'people_count', i.people_count,
      'resident_note', i.note,
      'vulnerable', to_jsonb(i.vulnerable),
      'status', i.status,
      'accepted_at', (select max(e.at) from public.incident_event e
                       where e.incident_id = i.incident_id and e.kind = 'enRoute'),
      'on_scene_at', (select max(e.at) from public.incident_event e
                       where e.incident_id = i.incident_id and e.kind = 'onScene'),
      'real_emergency', i.real_emergency,
      'not_real_reason', i.not_real_reason,
      'people_found', i.people_found,
      'route', (select jsonb_build_object('polyline', d.route) || coalesce(d.route_plan, '{}'::jsonb)
                  from public.dispatch d
                 where d.incident_id = i.incident_id and d.unit_id = i.assigned_unit_id
                   and d.completion_time is null and d.route is not null
                 order by d.dispatch_time desc limit 1),
      'resident_latitude', i.last_latitude,
      'resident_longitude', i.last_longitude,
      'resident_location_at', i.last_location_at,
      'cancel_requested_at', i.cancel_requested_at,
      'resident_name', (select nullif(btrim(r.fullname), '')
                          from public.manila_resident r
                         where i.origin = 'sos'
                           and i.anonymized_at is null
                           and r.manila_resident_id = i.manila_resident_id),
      'highest_alarm', (select e.detail
                          from public.incident_event e
                         where e.incident_id = i.incident_id
                           and e.kind = 'fireStage'
                           and array_position(private.fire_stages(), e.detail) between 2 and 12
                         order by array_position(private.fire_stages(), e.detail) desc
                         limit 1)
    ) order by i.received_at), '[]'::jsonb)
  from public.incident_report i
  where (select private.current_staff_role()) = 'responder'
    and i.assigned_unit_id = (select private.current_staff_unit())
    and i.status in ('assigned', 'enRoute', 'onScene')
    and i.done_reported_at is null
$$;
