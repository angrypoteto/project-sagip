-- The typhoon tracker on the Heatmap page (Joshua, 2026-11-02): where a
-- tropical cyclone is and is going, and PAGASA's warnings, beside the
-- 72-hour forecast so one can be checked against the other.
--
-- The ingest-storms Edge Function fills two tables every 30 minutes:
--
-- * storm_track: tropical cyclones from GDACS (the UN and EU's Global
--   Disaster Alert and Coordination System, JTWC advisories) whose track
--   touches the Philippine Area of Responsibility: the track (past and
--   forecast positions, each with its category), the wind zones (60, 90,
--   and 120 km/h), and the forecast cone.
-- * pagasa_warning: PAGASA's public CAP alerts (publicalert.pagasa.dost.
--   gov.ph): tropical cyclone warnings with their wind signal and
--   provinces, and general flood advisories with their areas' outlines.
--
-- Satellite rainfall (NASA IMERG) is drawn from NASA's own map tiles and
-- stores nothing here. Dispatchers and admins read both tables; only the
-- server writes them (save_hazard_feeds, service role).

create table public.storm_track (
  event_id int primary key,
  episode_id int not null,
  name text not null,
  alert_level text not null check (alert_level in ('Green', 'Orange', 'Red')),
  is_current boolean not null default false,
  from_at timestamptz not null,
  to_at timestamptz not null,
  -- When GDACS last changed the event.
  updated_at timestamptz,
  max_wind_kmh real,
  source text,
  -- [{t, lat, lng, category, forecast}], oldest first.
  track jsonb not null default '[]' check (jsonb_typeof(track) = 'array'),
  -- [{kmh, rings: [[[lat, lng], ...], ...]}].
  wind_zones jsonb not null default '[]' check (jsonb_typeof(wind_zones) = 'array'),
  -- [[[lat, lng], ...], ...].
  cone jsonb not null default '[]' check (jsonb_typeof(cone) = 'array'),
  fetched_at timestamptz not null default now()
);

create table public.pagasa_warning (
  id text primary key,
  -- The feed's folder: wcp (tropical cyclone warning), gfa (general flood
  -- advisory), and others PAGASA adds.
  kind text not null,
  event text not null,
  headline text,
  description text,
  instruction text,
  msg_type text,
  response_type text,
  severity text,
  urgency text,
  signal_level int check (signal_level between 0 and 5),
  sent_at timestamptz not null,
  expires_at timestamptz,
  -- The warnings this one updates or cancels.
  refs text[] not null default '{}',
  -- [{name, rings: [[[lat, lng], ...], ...]}]; rings empty when PAGASA
  -- names the area only.
  areas jsonb not null default '[]' check (jsonb_typeof(areas) = 'array'),
  fetched_at timestamptz not null default now()
);

create index pagasa_warning_sent_idx on public.pagasa_warning (sent_at desc);
create index storm_track_to_idx on public.storm_track (to_at desc);

alter table public.storm_track enable row level security;
alter table public.pagasa_warning enable row level security;

create policy "storm track: dispatchers and admins" on public.storm_track
  for select to authenticated
  using ((select private.is_dispatcher()));
create policy "pagasa warning: dispatchers and admins" on public.pagasa_warning
  for select to authenticated
  using ((select private.is_dispatcher()));

revoke all on public.storm_track, public.pagasa_warning from anon;
revoke insert, update, delete, truncate on public.storm_track, public.pagasa_warning from authenticated;
grant select on public.storm_track, public.pagasa_warning to authenticated;

-- What one run of ingest-storms read: storms are replaced as GDACS updates
-- them (null when GDACS could not be read), warnings are kept as first
-- read (PAGASA issues a new one for each change). Returns how many of each
-- were saved.
create function public.save_hazard_feeds(p_storms jsonb, p_warnings jsonb)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  n_storms int := 0;
  n_warnings int := 0;
begin
  if jsonb_typeof(coalesce(p_storms, '[]')) <> 'array'
     or jsonb_typeof(coalesce(p_warnings, '[]')) <> 'array' then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  -- Null storms: GDACS could not be read this time; keep what is there.
  if p_storms is not null then
    insert into public.storm_track as s
      (event_id, episode_id, name, alert_level, is_current, from_at, to_at, updated_at,
       max_wind_kmh, source, track, wind_zones, cone, fetched_at)
    select (x ->> 'event_id')::int, (x ->> 'episode_id')::int, x ->> 'name', x ->> 'alert_level',
           coalesce((x ->> 'is_current')::boolean, false), (x ->> 'from_at')::timestamptz,
           (x ->> 'to_at')::timestamptz, (x ->> 'updated_at')::timestamptz,
           (x ->> 'max_wind_kmh')::real, x ->> 'source',
           coalesce(x -> 'track', '[]'), coalesce(x -> 'wind_zones', '[]'), coalesce(x -> 'cone', '[]'), now()
      from jsonb_array_elements(coalesce(p_storms, '[]')) x
    on conflict (event_id) do update set
      episode_id = excluded.episode_id, name = excluded.name, alert_level = excluded.alert_level,
      is_current = excluded.is_current, from_at = excluded.from_at, to_at = excluded.to_at,
      updated_at = excluded.updated_at, max_wind_kmh = excluded.max_wind_kmh, source = excluded.source,
      track = excluded.track, wind_zones = excluded.wind_zones, cone = excluded.cone,
      fetched_at = excluded.fetched_at;
    get diagnostics n_storms = row_count;
    -- A storm GDACS no longer lists as current is over.
    update public.storm_track s
       set is_current = false
     where s.is_current
       and not exists (select 1 from jsonb_array_elements(coalesce(p_storms, '[]')) x
                        where (x ->> 'event_id')::int = s.event_id);
  end if;
  insert into public.pagasa_warning
    (id, kind, event, headline, description, instruction, msg_type, response_type, severity,
     urgency, signal_level, sent_at, expires_at, refs, areas)
  select x ->> 'id', x ->> 'kind', x ->> 'event', x ->> 'headline', x ->> 'description',
         x ->> 'instruction', x ->> 'msg_type', x ->> 'response_type', x ->> 'severity',
         x ->> 'urgency', (x ->> 'signal_level')::int, (x ->> 'sent_at')::timestamptz,
         (x ->> 'expires_at')::timestamptz,
         coalesce(array(select jsonb_array_elements_text(x -> 'refs')), '{}'),
         coalesce(x -> 'areas', '[]')
    from jsonb_array_elements(coalesce(p_warnings, '[]')) x
  on conflict (id) do nothing;
  get diagnostics n_warnings = row_count;
  return jsonb_build_object('storms', n_storms, 'warnings', n_warnings);
end $$;

revoke all on function public.save_hazard_feeds(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.save_hazard_feeds(jsonb, jsonb) to service_role;

-- Calls ingest-storms with the shared secret (as call_run_forecast does).
create function private.call_ingest_storms()
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
    url := 'https://imssgenjfirpohkwxwbv.supabase.co/functions/v1/ingest-storms',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-sagip-key', v_key),
    timeout_milliseconds := 60000);
end $$;

revoke all on function private.call_ingest_storms() from public, anon, authenticated;

-- Every 30 minutes, at 10 and 40 past.
select cron.schedule('ingest-storms', '10,40 * * * *', 'select private.call_ingest_storms()');
