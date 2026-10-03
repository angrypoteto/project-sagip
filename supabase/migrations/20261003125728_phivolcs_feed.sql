-- PHIVOLCS earthquakes near Manila, for the advisory relay (FR14; plan
-- Phase 6 "Confirm the PHIVOLCS source; build ingest-phivolcs").
--
-- Earthquakes are relayed, never forecast (CLAUDE.md scope). Every 15
-- minutes the ingest-phivolcs Edge Function reads PHIVOLCS's public list of
-- recent earthquakes and keeps the ones within 300 km of Manila from the
-- last 48 hours (record_phivolcs_events). Nothing reaches residents by
-- itself: the Weather page (D10) lists them, and a dispatcher may pass one
-- on with "Relay as advisory" (issue_alert, source PHIVOLCS). The feed's
-- health is a third row of feed_status (`phivolcs`).

alter table public.feed_status drop constraint feed_status_source_check;
alter table public.feed_status add constraint feed_status_source_check
  check (source in ('pagasa_rainfall', 'pagasa_cyclone', 'phivolcs'));
comment on table public.feed_status is
  'Health of the PAGASA and PHIVOLCS feeds, one row per source. Dispatchers and admins read it.';

create table public.phivolcs_event (
  event_key text primary key,
  occurred_at timestamptz not null,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  depth_km numeric not null check (depth_km >= 0),
  magnitude numeric not null check (magnitude between 0 and 10),
  location text not null,
  distance_km numeric not null check (distance_km >= 0),
  bulletin_url text,
  first_seen_at timestamptz not null default now()
);
comment on table public.phivolcs_event is
  'PHIVOLCS earthquakes within 300 km of Manila (ingest-phivolcs). Dispatchers and admins read it.';
create index phivolcs_event_time_idx on public.phivolcs_event (occurred_at desc);
alter table public.phivolcs_event enable row level security;
create policy "phivolcs events: dispatchers and admins" on public.phivolcs_event
  for select to authenticated using ((select private.is_dispatcher()));
grant select on public.phivolcs_event to authenticated;
alter publication supabase_realtime add table public.phivolcs_event;

-- Adds the events not seen before; returns how many were new. PHIVOLCS
-- sometimes revises an event's magnitude or place: the newest reading wins.
create function public.record_phivolcs_events(p_events jsonb)
returns int
language plpgsql security definer set search_path = ''
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
  return n;
end $$;

create function private.call_ingest_phivolcs()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_key text;
begin
  select s.decrypted_secret into v_key from vault.decrypted_secrets s where s.name = 'send_alerts_key';
  if v_key is null then
    return;
  end if;
  perform net.http_post(
    url := 'https://imssgenjfirpohkwxwbv.supabase.co/functions/v1/ingest-phivolcs',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-sagip-key', v_key),
    timeout_milliseconds := 60000);
end $$;

revoke all on function public.record_phivolcs_events(jsonb) from public, anon, authenticated;
grant execute on function public.record_phivolcs_events(jsonb) to service_role;
revoke all on function private.call_ingest_phivolcs() from public, anon, authenticated;

-- Every 15 minutes: PHIVOLCS posts events within minutes, and the page is
-- about 120 KB compressed.
select cron.schedule('ingest-phivolcs', '*/15 * * * *', 'select private.call_ingest_phivolcs()');
