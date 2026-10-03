-- The PAGASA feed (FR5): the ingest-pagasa Edge Function reads PAGASA's
-- public pages every 10 minutes and records Manila's readings here; the
-- threshold engine (alert_engine) raises or ends alerts from them.
-- Joshua decided on 2026-10-03 to parse PAGASA's pages instead of waiting
-- for API access (plan Q35, docs/PAGASA-PARSER-PLAN.md).
--
-- Adds:
-- - feed_status: how each source went last (for D10's feed line);
-- - record_pagasa_reading(): a new weather_alert row only when something
--   changed; nothing while simulation mode is on;
-- - record_feed_status();
-- - a pg_cron job that calls the function every 10 minutes (pg_net, with
--   the shared secret send-alerts already uses).
-- Nothing existing changes.

create table public.feed_status (
  source text primary key check (source in ('pagasa_rainfall', 'pagasa_cyclone')),
  checked_at timestamptz not null default now(),
  ok boolean not null,
  last_success_at timestamptz,
  -- Why the last check failed; cleared by the next success.
  last_error text,
  -- Failed checks in a row.
  failures int not null default 0 check (failures >= 0),
  -- What the last successful check read (warning number, bulletin number,
  -- levels), for the Weather page.
  seen jsonb not null default '{}'
);
comment on table public.feed_status is
  'Health of the PAGASA feed, one row per source (ingest-pagasa). Dispatchers and admins read it.';
alter table public.feed_status enable row level security;
create policy "feed status: dispatchers and admins" on public.feed_status
  for select to authenticated using ((select private.is_dispatcher()));
grant select on public.feed_status to authenticated;
alter publication supabase_realtime add table public.feed_status;

-- How one source's check went. Service role only (the Edge Function).
create or replace function public.record_feed_status(
  p_source text,
  p_ok boolean,
  p_error text default null,
  p_seen jsonb default null
)
returns void
language sql security definer set search_path = ''
as $$
  insert into public.feed_status as f
    (source, checked_at, ok, last_success_at, last_error, failures, seen)
  values (
    p_source, now(), p_ok,
    case when p_ok then now() end,
    case when p_ok then null else left(coalesce(p_error, 'unknown error'), 300) end,
    case when p_ok then 0 else 1 end,
    coalesce(case when p_ok then p_seen end, '{}'))
  on conflict (source) do update set
    checked_at = now(),
    ok = excluded.ok,
    last_success_at = case when excluded.ok then now() else f.last_success_at end,
    last_error = excluded.last_error,
    failures = case when excluded.ok then 0 else f.failures + 1 end,
    seen = case when excluded.ok then excluded.seen else f.seen end;
$$;

-- Manila's readings from PAGASA. A null means the source could not be
-- read: the last real value is kept. A row is added only when a value
-- changed, or when the current row is a simulated one. Returns 'recorded',
-- 'unchanged', or 'paused' (simulation mode is on, so the demo keeps its
-- simulated weather). Service role only.
create or replace function public.record_pagasa_reading(
  p_rainfall numeric,
  p_signal int,
  p_surge_m numeric
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  last_row public.weather_alert;
  last_real public.weather_alert;
  v_rain numeric;
  v_signal int;
  v_surge numeric;
begin
  if private.setting_flag('demo.simulation') then
    return 'paused';
  end if;
  if p_rainfall < 0 or p_signal not between 0 and 5 or p_surge_m < 0 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select * into last_row from public.weather_alert w
   where w.barangay is null order by w.issued_at desc, w.alert_id desc limit 1;
  select * into last_real from public.weather_alert w
   where w.barangay is null and not w.is_simulated
   order by w.issued_at desc, w.alert_id desc limit 1;

  v_rain := coalesce(p_rainfall, last_real.rainfall_intensity, 0);
  v_signal := coalesce(p_signal, last_real.signal_level, 0);
  v_surge := coalesce(p_surge_m, last_real.storm_surge_m, 0);

  if last_row.alert_id is not null and not last_row.is_simulated
     and last_row.rainfall_intensity = v_rain
     and last_row.signal_level = v_signal
     and coalesce(last_row.storm_surge_m, 0) = v_surge then
    return 'unchanged';
  end if;

  insert into public.weather_alert
    (signal_level, rainfall_intensity, storm_surge_m, issued_at, is_simulated)
  values (v_signal, v_rain, v_surge, now(), false);
  return 'recorded';
end $$;

revoke all on function public.record_feed_status(text, boolean, text, jsonb) from public, anon, authenticated;
revoke all on function public.record_pagasa_reading(numeric, int, numeric) from public, anon, authenticated;
grant execute on function public.record_feed_status(text, boolean, text, jsonb) to service_role;
grant execute on function public.record_pagasa_reading(numeric, int, numeric) to service_role;

-- ------------------------------------------------------------ schedule

-- Calls ingest-pagasa with the shared secret (as private.call_sender does).
create or replace function private.call_ingest_pagasa()
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
    url := 'https://imssgenjfirpohkwxwbv.supabase.co/functions/v1/ingest-pagasa',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-sagip-key', v_key),
    timeout_milliseconds := 60000);
end $$;
revoke all on function private.call_ingest_pagasa() from public, anon, authenticated;

create extension if not exists pg_cron;
-- Every 10 minutes: PAGASA updates warnings every few hours, and the
-- feed must stay light on PAGASA's servers.
select cron.schedule('ingest-pagasa', '*/10 * * * *', 'select private.call_ingest_pagasa()');
