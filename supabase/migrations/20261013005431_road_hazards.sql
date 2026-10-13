-- Where routes are slowed, for the responder's phone (Joshua, 2026-10-13).
--
-- The dashboard already routes around confirmed floods (plan 10.2); fires
-- were added in the apps on the same day. The phone works out its own route
-- with Dijkstra on every new position, but a responder may read only the
-- incident assigned to their unit, so the phone did not know where the
-- other floods and fires were and could lead a crew through one.
--
-- road_hazards() gives staff the confirmed, open floods and fires: the type
-- and the position, nothing about who reported them. The caller's own
-- incident is left out (its street is where the unit has to go). Residents
-- and signed-out callers are refused.

create function public.road_hazards()
returns table (type text, latitude double precision, longitude double precision)
language plpgsql stable security definer set search_path = ''
as $$
declare
  me public.staff;
  mine text;
begin
  select * into me from public.staff s
   where s.id = (select auth.uid()) and s.deactivated_at is null;
  if me.id is null then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  select u.current_incident_id into mine
    from public.response_unit u where u.unit_id = me.unit_id;
  return query
    select coalesce(i.emergency_type, i.suggested_type), i.latitude, i.longitude
      from public.incident_report i
     where coalesce(i.emergency_type, i.suggested_type) in ('flood', 'fire')
       and (i.verification_method is not null or i.origin = 'crowdCluster')
       and i.status <> 'resolved'
       and not i.false_report
       and not i.cancelled
       and i.incident_id is distinct from mine
     order by i.received_at, i.incident_id;
end $$;

comment on function public.road_hazards() is
  'Confirmed open floods and fires (type and position only) for routing; staff only, never the caller''s own incident.';

revoke execute on function public.road_hazards() from public, anon;
grant execute on function public.road_hazards() to authenticated;
