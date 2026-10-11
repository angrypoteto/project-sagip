-- River levels for the Weather page (FR5; plan Phase 6 "Confirm the EFCOS
-- format; parse stations near Manila").
--
-- EFCOS itself has no public feed. PAGASA publishes the levels of the same
-- rivers (the Pasig-Marikina-Tullahan flood forecasting and warning
-- system) with each station's alert, alarm, and critical level. Every 10
-- minutes the ingest-efcos Edge Function reads that list and keeps each
-- station's newest reading (record_river_levels). Nothing reaches
-- residents by itself: D10 lists the stations, and a dispatcher may pass a
-- level on with "Relay as advisory" (issue_alert, source EFCOS). A sensor
-- can misread, so a person decides. The feed's health is a row of
-- feed_status (`efcos`).

alter table public.feed_status drop constraint feed_status_source_check;
alter table public.feed_status add constraint feed_status_source_check
  check (source in ('pagasa_rainfall', 'pagasa_cyclone', 'phivolcs', 'efcos'));
comment on table public.feed_status is
  'Health of the PAGASA, PHIVOLCS, and river level feeds, one row per source. Dispatchers and admins read it.';

create table public.river_level (
  station_code text primary key,
  name text not null,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  observed_at timestamptz not null,
  level_m numeric not null,
  -- Change since the reading before, as PAGASA gives it.
  change_m numeric,
  alert_m numeric,
  alarm_m numeric,
  critical_m numeric,
  -- PAGASA marks some readings with (*).
  flagged boolean not null default false,
  -- The highest of the station's own levels the water has reached; null
  -- when the station has none.
  state text generated always as (
    case
      when alert_m is null then null
      when critical_m is not null and level_m >= critical_m then 'critical'
      when alarm_m is not null and level_m >= alarm_m then 'alarm'
      when level_m >= alert_m then 'alert'
      else 'normal'
    end) stored,
  updated_at timestamptz not null default now()
);
comment on table public.river_level is
  'Newest water level of each Pasig-Marikina-Tullahan station (ingest-efcos, from PAGASA). Dispatchers and admins read it.';
alter table public.river_level enable row level security;
create policy "river levels: dispatchers and admins" on public.river_level
  for select to authenticated using ((select private.is_dispatcher()));
grant select on public.river_level to authenticated;
alter publication supabase_realtime add table public.river_level;

-- Keeps each station's newest reading; returns how many stations changed.
-- An older reading than the one kept is ignored.
create function public.record_river_levels(p_levels jsonb)
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  n int;
begin
  if jsonb_typeof(p_levels) <> 'array' then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  with incoming as (
    select distinct on (e ->> 'code')
           left(e ->> 'code', 20) as station_code,
           left(e ->> 'name', 80) as name,
           (e ->> 'latitude')::double precision as latitude,
           (e ->> 'longitude')::double precision as longitude,
           (e ->> 'observed_at')::timestamptz as observed_at,
           (e ->> 'level_m')::numeric as level_m,
           (e ->> 'change_m')::numeric as change_m,
           (e ->> 'alert_m')::numeric as alert_m,
           (e ->> 'alarm_m')::numeric as alarm_m,
           (e ->> 'critical_m')::numeric as critical_m,
           coalesce((e ->> 'flagged')::boolean, false) as flagged
      from jsonb_array_elements(p_levels) e
     where coalesce(e ->> 'code', '') <> ''
     order by e ->> 'code', (e ->> 'observed_at')::timestamptz desc
  ), upserted as (
    insert into public.river_level as r
      (station_code, name, latitude, longitude, observed_at, level_m, change_m,
       alert_m, alarm_m, critical_m, flagged)
    select * from incoming
    on conflict (station_code) do update set
      name = excluded.name, latitude = excluded.latitude, longitude = excluded.longitude,
      observed_at = excluded.observed_at, level_m = excluded.level_m,
      change_m = excluded.change_m, alert_m = excluded.alert_m,
      alarm_m = excluded.alarm_m, critical_m = excluded.critical_m,
      flagged = excluded.flagged, updated_at = now()
      where excluded.observed_at > r.observed_at
    returning 1
  )
  select count(*) into n from upserted;
  return n;
end $$;

create function private.call_ingest_efcos()
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
    url := 'https://imssgenjfirpohkwxwbv.supabase.co/functions/v1/ingest-efcos',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-sagip-key', v_key),
    timeout_milliseconds := 60000);
end $$;

revoke all on function public.record_river_levels(jsonb) from public, anon, authenticated;
grant execute on function public.record_river_levels(jsonb) to service_role;
revoke all on function private.call_ingest_efcos() from public, anon, authenticated;

-- Every 10 minutes: the stations report every 10 minutes, and the list is
-- about 6 KB.
select cron.schedule('ingest-efcos', '*/10 * * * *', 'select private.call_ingest_efcos()');
