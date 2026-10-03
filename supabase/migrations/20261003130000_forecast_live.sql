-- The forecast's simulated live feed (FR4; thesis scope: "LSTM and KDE
-- trained, simulated live feed"; plan 10.5).
--
-- forecast_model holds the exported model (supabase/data/
-- forecast_live_v1.json from ml/forecast/export_live.py): the three LSTMs'
-- weights and scalers, the replayed weather, the KDE density per barangay,
-- and the provisional rule (plan Q22). Service role only.
--
-- Every six hours pg_cron calls the run-forecast Edge Function (pg_net,
-- the send-alerts shared secret from Vault). It reads the active model and
-- the replay position (forecast_live_input), runs the LSTMs on the 14
-- replayed days ending there, and records the run for every barangay
-- (record_forecast_run), which moves the replay one day on and starts over
-- after the last day. Rows are marked simulated and name the replayed day
-- in model_version, so D8 and the resident's forecast tab say what they
-- are. Runs are kept (four a day, 897 rows each); removing old ones belongs
-- to the data retention rule that is still to be decided.
--
-- Loading the model (SQL editor, after the file is on GitHub):
--   select private.load_forecast_model(<the JSON>);
-- The README shows how to fetch it with pg_net.

create table public.forecast_model (
  version text primary key,
  model jsonb not null,
  is_active boolean not null default false,
  loaded_at timestamptz not null default now()
);
comment on table public.forecast_model is
  'The exported LSTM and KDE for the live forecast feed. Service role only.';
create unique index forecast_model_one_active on public.forecast_model (is_active) where is_active;
alter table public.forecast_model enable row level security;
-- No policies: only the service role reads it.

create table public.forecast_replay (
  id boolean primary key default true check (id),
  day_index int,
  last_run_at timestamptz,
  last_window_end date
);
comment on table public.forecast_replay is
  'Where the live forecast feed is in the replayed weather. Service role only.';
insert into public.forecast_replay default values;
alter table public.forecast_replay enable row level security;

-- Adds or replaces a model version, makes it the active one, and starts
-- the replay over.
create function private.load_forecast_model(p_model jsonb)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v text := p_model ->> 'version';
begin
  if v is null or jsonb_typeof(p_model -> 'hazards') <> 'object'
     or jsonb_typeof(p_model -> 'days') <> 'array'
     or jsonb_typeof(p_model -> 'weather') <> 'array'
     or jsonb_array_length(p_model -> 'days') <> jsonb_array_length(p_model -> 'weather')
     or not (p_model -> 'hazards' ?& array['flood', 'fire', 'storm_surge']) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  update public.forecast_model set is_active = false where is_active and version <> v;
  insert into public.forecast_model (version, model, is_active)
  values (v, p_model, true)
  on conflict (version) do update set model = excluded.model, is_active = true, loaded_at = now();
  update public.forecast_replay set day_index = null;
  return v || ': ' || jsonb_array_length(p_model -> 'days') || ' days';
end $$;

create function public.forecast_live_input()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object('version', m.version, 'model', m.model, 'day_index', r.day_index)
    from public.forecast_model m cross join public.forecast_replay r
   where m.is_active
$$;

-- One run: [p_levels] names the barangays above low on some hazard, as three
-- letters (l, m, h) for flood, fire, and storm surge; every other
-- barangay is low. Returns the rows written.
create function public.record_forecast_run(
  p_version text,
  p_window_end date,
  p_probabilities jsonb,
  p_levels jsonb,
  p_next_index int
)
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  issued timestamptz := now();
  n int;
begin
  if p_version is null or p_window_end is null or p_next_index is null
     or jsonb_typeof(p_levels) <> 'object'
     or exists (select 1 from jsonb_each_text(p_levels) e where e.value !~ '^[lmh]{3}$') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  insert into public.barangay_forecast
    (barangay, district, issued_at, valid_until, flood_risk, fire_risk, surge_risk, model_version, is_simulated)
  select b.name, b.district, issued, issued + interval '72 hours',
         case substr(coalesce(v.value, 'lll'), 1, 1) when 'h' then 'high' when 'm' then 'moderate' else 'low' end,
         case substr(coalesce(v.value, 'lll'), 2, 1) when 'h' then 'high' when 'm' then 'moderate' else 'low' end,
         case substr(coalesce(v.value, 'lll'), 3, 1) when 'h' then 'high' when 'm' then 'moderate' else 'low' end,
         p_version || ' live (sample data, replaying ' || to_char(p_window_end, 'FMDD Mon YYYY')
           || ', provisional levels)',
         true
    from public.barangay b
    left join jsonb_each_text(p_levels) v on v.key = b.name;
  get diagnostics n = row_count;
  update public.forecast_replay
     set day_index = p_next_index, last_run_at = issued, last_window_end = p_window_end;
  return n;
end $$;

create function private.call_run_forecast()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_key text;
begin
  select s.decrypted_secret into v_key from vault.decrypted_secrets s where s.name = 'send_alerts_key';
  if v_key is null or not exists (select 1 from public.forecast_model m where m.is_active) then
    return;
  end if;
  perform net.http_post(
    url := 'https://imssgenjfirpohkwxwbv.supabase.co/functions/v1/run-forecast',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-sagip-key', v_key),
    timeout_milliseconds := 60000);
end $$;

revoke all on function private.load_forecast_model(jsonb) from public, anon, authenticated;
grant execute on function private.load_forecast_model(jsonb) to service_role;
revoke all on function public.forecast_live_input() from public, anon, authenticated;
grant execute on function public.forecast_live_input() to service_role;
revoke all on function public.record_forecast_run(text, date, jsonb, jsonb, int) from public, anon, authenticated;
grant execute on function public.record_forecast_run(text, date, jsonb, jsonb, int) to service_role;
revoke all on function private.call_run_forecast() from public, anon, authenticated;

-- D8 finds the newest run by its issue time.
create index if not exists barangay_forecast_issued_idx on public.barangay_forecast (issued_at desc);

-- Every six hours, at five past: D8 moves during a day of demos without
-- filling the table.
select cron.schedule('run-forecast', '5 */6 * * *', 'select private.call_run_forecast()');
