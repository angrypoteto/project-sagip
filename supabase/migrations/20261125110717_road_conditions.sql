-- Live road conditions from TomTom (Joshua, 2026-11-25).
--
-- Every 5 minutes the road-conditions Edge Function asks TomTom's Traffic
-- Incidents API what it reports inside a box around Manila: jams, closed
-- roads, and flooded roads. This keeps the latest answer so the dashboard
-- map can draw the roads (red for heavy jams, dashed red for closed, blue
-- for flooded) and routing can slow them (Dijkstra stays the same; only the
-- road times change).
--
-- It is outside data: it never creates or confirms an incident (FR7). It
-- holds no personal data: road names, a line, and how slow.
--
-- - road_condition: the latest snapshot. Each run replaces it (a cache of
--   TomTom's answer, not a record); roads that do not touch Manila's
--   outline are dropped.
-- - road_feed: one row, when the last run was and whether it worked.
-- - save_road_conditions() and road_feed_failed(): the Edge Function only
--   (service role).
-- - road_conditions(): staff only (dispatchers, admins, responders).
-- - pg_cron every 5 minutes, with the shared secret as run-forecast uses.

create table public.road_condition (
  condition_id text primary key,
  kind text not null check (kind in ('jam', 'closed', 'flooding')),
  -- TomTom's magnitude of delay: 0 unknown, 1 minor, 2 moderate, 3 major,
  -- 4 undefined (used for closures).
  severity smallint not null default 0 check (severity between 0 and 4),
  road text check (char_length(road) <= 200),
  from_place text check (char_length(from_place) <= 200),
  to_place text check (char_length(to_place) <= 200),
  delay_seconds integer check (delay_seconds >= 0),
  length_meters integer check (length_meters >= 0),
  since timestamptz,
  -- [[lng, lat], ...], at least two points.
  path jsonb not null check (jsonb_typeof(path) = 'array' and jsonb_array_length(path) >= 2),
  fetched_at timestamptz not null
);
comment on table public.road_condition is
  'Latest TomTom road report inside Manila: jams, closed and flooded roads (no personal data). Replaced every run; server writes only.';
alter table public.road_condition enable row level security;
revoke all on public.road_condition from anon, authenticated;

create table public.road_feed (
  id boolean primary key default true check (id),
  fetched_at timestamptz,
  ok boolean not null default false,
  message text check (char_length(message) <= 300),
  kept integer not null default 0,
  dropped integer not null default 0
);
comment on table public.road_feed is
  'When the TomTom road feed last ran and whether it worked. One row.';
alter table public.road_feed enable row level security;
revoke all on public.road_feed from anon, authenticated;
insert into public.road_feed (id) values (true);

-- Replaces the snapshot with [p_items] (each: id, kind, severity, road,
-- from, to, delay, length, since, path), keeping only roads that touch
-- Manila. Returns how many were kept and dropped.
create function public.save_road_conditions(p_items jsonb, p_fetched_at timestamptz)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_kept integer;
  v_total integer;
begin
  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'bad_items' using errcode = 'P0001';
  end if;
  v_total := jsonb_array_length(p_items);
  delete from public.road_condition where true;
  insert into public.road_condition (
    condition_id, kind, severity, road, from_place, to_place,
    delay_seconds, length_meters, since, path, fetched_at)
  select distinct on (x->>'id')
         x->>'id', x->>'kind', coalesce((x->>'severity')::smallint, 0),
         left(x->>'road', 200), left(x->>'from', 200), left(x->>'to', 200),
         (x->>'delay')::integer, (x->>'length')::integer,
         (x->>'since')::timestamptz, x->'path', p_fetched_at
    from jsonb_array_elements(p_items) x
   where x->>'id' is not null
     and x->>'kind' in ('jam', 'closed', 'flooding')
     and jsonb_typeof(x->'path') = 'array'
     and jsonb_array_length(x->'path') >= 2
     and exists (
       select 1 from public.manila_outline o
        where extensions.st_intersects(
          o.boundary,
          extensions.st_setsrid(
            extensions.st_geomfromgeojson(
              jsonb_build_object('type', 'LineString', 'coordinates', x->'path')::text),
            4326)::extensions.geography));
  get diagnostics v_kept = row_count;
  update public.road_feed
     set fetched_at = p_fetched_at, ok = true, message = null,
         kept = v_kept, dropped = v_total - v_kept
   where id;
  return jsonb_build_object('kept', v_kept, 'dropped', v_total - v_kept);
end $$;

comment on function public.save_road_conditions(jsonb, timestamptz) is
  'road-conditions Edge Function only: replaces the TomTom snapshot, keeping roads inside Manila.';

-- A failed run: the last snapshot stays; the apps show how old it is.
create function public.road_feed_failed(p_message text)
returns void
language sql security definer set search_path = ''
as $$
  update public.road_feed set ok = false, message = left(p_message, 300) where id;
$$;

revoke execute on function public.save_road_conditions(jsonb, timestamptz) from public, anon, authenticated;
revoke execute on function public.road_feed_failed(text) from public, anon, authenticated;
grant execute on function public.save_road_conditions(jsonb, timestamptz) to service_role;
grant execute on function public.road_feed_failed(text) to service_role;

-- What the maps draw and routing slows: staff only.
create function public.road_conditions()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not exists (select 1 from public.staff s
                  where s.id = (select auth.uid()) and s.deactivated_at is null) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  return (
    select jsonb_build_object(
      'fetched_at', f.fetched_at,
      'ok', f.ok,
      'items', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', c.condition_id, 'kind', c.kind, 'severity', c.severity,
                 'road', c.road, 'from', c.from_place, 'to', c.to_place,
                 'delay', c.delay_seconds, 'length', c.length_meters,
                 'since', c.since, 'path', c.path)
                 order by c.kind, c.condition_id)
          from public.road_condition c), '[]'::jsonb))
      from public.road_feed f where f.id);
end $$;

comment on function public.road_conditions() is
  'The latest TomTom jams, closed and flooded roads in Manila with when they were fetched; staff only.';

revoke execute on function public.road_conditions() from public, anon;
grant execute on function public.road_conditions() to authenticated;

-- The 5-minute job (about 290 TomTom requests a day; the free tier allows 2,500).
create function private.call_road_conditions()
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
    url := 'https://imssgenjfirpohkwxwbv.supabase.co/functions/v1/road-conditions',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-sagip-key', v_key),
    timeout_milliseconds := 30000);
end $$;

revoke execute on function private.call_road_conditions() from public, anon, authenticated;

select cron.schedule('road-conditions', '*/5 * * * *', 'select private.call_road_conditions()');
