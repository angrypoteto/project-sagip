-- FR14 (Joshua, 2026-11-03: "make the system now 100%"): PHIVOLCS
-- earthquakes near Manila are passed on to residents by themselves, as
-- informational notices. Until now a dispatcher had to relay each one by
-- hand from D10 (that stays possible).
--
-- 1. Settings (A3, provisional until MDRRMD's SOP): alerts.quake_relay (on),
--    alerts.quake_min_magnitude (5), alerts.quake_max_km (150 km from
--    Manila City Hall): roughly the quakes felt in Manila.
-- 2. phivolcs_event.relayed_alert_id: the notice an earthquake became, so
--    each is passed on once.
-- 3. private.relay_phivolcs_events(), called at the end of
--    record_phivolcs_events() (every 15 minutes): each earthquake from the
--    last 3 hours that meets the settings becomes one info alert for all of
--    Manila (source phivolcs), worded as D10's "Relay as advisory" draft,
--    shown in the app and sent by push only (never SMS or Facebook: it is
--    information, and texts cost), ending after 24 hours. A magnitude that
--    PHIVOLCS revises upward past the setting is passed on then.

insert into public.app_setting (key, category, value, min_value, max_value, description) values
  ('alerts.quake_relay', 'alerts', 'true', null, null,
   'Earthquakes PHIVOLCS reports near Manila are passed on to residents as information, in the app and by push'),
  ('alerts.quake_min_magnitude', 'alerts', '5', 3, 8,
   'Earthquakes of at least this magnitude are passed on to residents'),
  ('alerts.quake_max_km', 'alerts', '150', 10, 300,
   'Earthquakes at most this many km from Manila City Hall are passed on to residents')
on conflict (key) do nothing;

alter table public.phivolcs_event
  add column relayed_alert_id text references public.public_alert (alert_id);

comment on column public.phivolcs_event.relayed_alert_id is
  'The informational alert this earthquake was passed on as (relay_phivolcs_events), once.';

create or replace function private.relay_phivolcs_events()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  q public.phivolcs_event;
  n int := 0;
  new_id text;
  mag text;
begin
  if not coalesce(private.setting_flag('alerts.quake_relay'), false) then
    return 0;
  end if;
  for q in
    select * from public.phivolcs_event e
     where e.relayed_alert_id is null
       and e.occurred_at > now() - interval '3 hours'
       and e.magnitude >= private.setting_number('alerts.quake_min_magnitude')
       and e.distance_km <= private.setting_number('alerts.quake_max_km')
     order by e.occurred_at
     for update
  loop
    mag := to_char(q.magnitude, 'FM990.0');
    insert into public.public_alert
      (source, level, title, body, guidance, barangays, expires_at, is_simulated)
    values (
      'phivolcs', 'info',
      format('Magnitude %s earthquake, %s km from Manila', mag, round(q.distance_km)),
      format('PHIVOLCS reports a magnitude %s earthquake at %s, %s, %s km deep. '
             'Check your home for cracks and be ready for aftershocks.',
             mag,
             to_char(q.occurred_at at time zone 'Asia/Manila', 'Mon FMDD, YYYY FMHH12:MI AM'),
             q.location, round(q.depth_km)),
      array['Drop, cover, and hold on if the ground shakes again',
            'Stay away from damaged buildings and walls',
            'Call MDRRMD if someone is hurt or trapped'],
      '{}', now() + interval '24 hours',
      coalesce(private.setting_flag('demo.simulation'), false))
    returning alert_id into new_id;
    -- Information only: in the app and by push, never by SMS or on Facebook.
    update public.alert_delivery set status = 'off'
     where alert_id = new_id and channel in ('sms', 'facebook') and status = 'queued';
    update public.phivolcs_event set relayed_alert_id = new_id where event_key = q.event_key;
    n := n + 1;
  end loop;
  return n;
end $$;

revoke all on function private.relay_phivolcs_events() from public, anon, authenticated;

create or replace function public.record_phivolcs_events(p_events jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n int;
begin
  if jsonb_typeof(p_events) <> 'array' then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  with incoming as (
    select e ->> 'key' as event_key,
           (e ->> 'occurred_at')::timestamptz as occurred_at,
           (e ->> 'latitude')::double precision as latitude,
           (e ->> 'longitude')::double precision as longitude,
           (e ->> 'depth_km')::numeric as depth_km,
           (e ->> 'magnitude')::numeric as magnitude,
           left(e ->> 'location', 200) as location,
           (e ->> 'distance_km')::numeric as distance_km,
           left(e ->> 'bulletin_url', 500) as bulletin_url
      from jsonb_array_elements(p_events) e
     where (e ->> 'distance_km')::numeric <= 300
  ), upserted as (
    insert into public.phivolcs_event as p
      (event_key, occurred_at, latitude, longitude, depth_km, magnitude, location, distance_km, bulletin_url)
    select * from incoming
    on conflict (event_key) do update set
      magnitude = excluded.magnitude, location = excluded.location,
      depth_km = excluded.depth_km, bulletin_url = excluded.bulletin_url
    returning (xmax = 0) as added
  )
  select count(*) filter (where added) into n from upserted;
  -- FR14 (2026-11-03): pass the felt ones on to residents.
  perform private.relay_phivolcs_events();
  return n;
end $$;
