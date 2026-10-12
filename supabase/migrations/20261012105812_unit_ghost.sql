-- A unit's station and its crew's live position are two things, and the
-- map shows both (Joshua, 2026-10-12): the station pin and a ghost for
-- where the crew's phone is; on a job the live position is the main one
-- and the station the faint one.
--
-- So a unit is no longer moved back to its station when it becomes
-- available (migration unit_home did that this morning): last_latitude /
-- last_longitude / last_location_at are again only what the crew's phone
-- reported, and home_latitude / home_longitude are the station.
--
-- Adds set_unit_home(): an admin sets or clears a unit's station position
-- (A2), audited.

drop trigger response_unit_returns_home on public.response_unit;

-- Kept as a function that changes nothing: removing a function is left to
-- Joshua in the SQL editor (`drop function private.unit_returns_home();`).
create or replace function private.unit_returns_home()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  return new;
end $$;

-- A unit that never sent a fix had its station in the "last position"
-- columns (that is how the ten stations were loaded). The station is in
-- home_* now; "last position" means a fix from the crew's phone only.
update public.response_unit
   set last_latitude = null, last_longitude = null
 where last_location_at is null and home_latitude is not null;

create function public.set_unit_home(
  p_unit_id text,
  p_latitude double precision,
  p_longitude double precision
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  u public.response_unit;
begin
  if (p_latitude is null) <> (p_longitude is null) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  -- A station in or beside the City of Manila.
  if p_latitude is not null
     and (p_latitude not between 14.50 and 14.70 or p_longitude not between 120.90 and 121.07) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select * into u from public.response_unit r where r.unit_id = p_unit_id for update;
  if u.unit_id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if u.home_latitude is not distinct from p_latitude
     and u.home_longitude is not distinct from p_longitude then
    return;
  end if;
  update public.response_unit
     set home_latitude = p_latitude, home_longitude = p_longitude
   where unit_id = u.unit_id;
  perform private.audit_admin(me, 'unitEdited', 'response_unit', u.unit_id,
    case when p_latitude is null then 'station position cleared'
         else 'station position set to ' || round(p_latitude::numeric, 5) || ', ' || round(p_longitude::numeric, 5) end);
end $$;

revoke all on function public.set_unit_home(text, double precision, double precision) from public, anon;
grant execute on function public.set_unit_home(text, double precision, double precision) to authenticated;
