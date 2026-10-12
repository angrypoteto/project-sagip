-- A unit goes back to its station on the map when its job is done
-- (Joshua, 2026-10-12: after a rescue the unit stayed drawn where the
-- resident was, because the crew's phone stops reporting once the job is
-- closed).
--
-- response_unit gets the station's own position (home). When a unit
-- becomes available again, its last position is set back to home and
-- marked as not a GPS fix (last_location_at empty). A new fix from the
-- crew's phone still moves it, as before. A unit with no home recorded
-- keeps its last position.
--
-- This is an assumption, not a measurement: the unit is shown at its
-- station from the moment it is free, though it is still driving back.

alter table public.response_unit
  add column home_latitude double precision check (home_latitude between -90 and 90),
  add column home_longitude double precision check (home_longitude between -180 and 180),
  add constraint response_unit_home_both check ((home_latitude is null) = (home_longitude is null));
comment on column public.response_unit.home_latitude is
  'The station''s position: where the unit is shown when it is available and has sent no fix since.';

-- The stations loaded from OpenStreetMap: a unit that has sent no fix is
-- still where it was loaded.
update public.response_unit
   set home_latitude = last_latitude, home_longitude = last_longitude
 where source is not null and last_location_at is null and last_latitude is not null;

-- The one that has been out since (supabase/data/manila_units.sql).
update public.response_unit
   set home_latitude = 14.58013, home_longitude = 121.00813
 where unit_id = 'unit-bfp-staana' and home_latitude is null;

create function private.unit_returns_home()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.status = 'available' and old.status is distinct from 'available'
     and new.home_latitude is not null then
    new.last_latitude := new.home_latitude;
    new.last_longitude := new.home_longitude;
    new.last_location_at := null;
  end if;
  return new;
end $$;

create trigger response_unit_returns_home
  before update of status on public.response_unit
  for each row execute function private.unit_returns_home();

-- Units already free and away from their station.
update public.response_unit
   set last_latitude = home_latitude, last_longitude = home_longitude, last_location_at = null
 where status = 'available' and home_latitude is not null
   and (last_latitude, last_longitude) is distinct from (home_latitude, home_longitude);
