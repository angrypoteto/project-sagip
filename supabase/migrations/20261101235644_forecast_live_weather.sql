-- The 72-hour forecast on live weather (Joshua, 2026-11-02, so the typhoon
-- tracker is a fair check on it). run-forecast now builds the 14 days to
-- yesterday from Open-Meteo and from SAGIP's own records, and falls back to
-- the replay when a source fails.
--
-- 1. forecast_live_days(): per day (Manila time), the highest PAGASA signal
--    and storm surge in force (weather_alert keeps a reading only when it
--    changes, so a reading lasts until the next), and the flood and fire
--    incidents received (not simulated, not false reports). Service role.
-- 2. record_forecast_run_labelled() takes the run's label and whether it
--    is simulated: a live run is labelled "live weather, 14 days to <day>
--    (sample-trained model, provisional levels)" and not marked simulated;
--    record_forecast_run() keeps its signature and records a replay as
--    before through it.

create or replace function public.forecast_live_days(p_from date, p_to date)
returns table (day date, signal int, surge_m real, flood int, fire int)
language sql
stable
security definer
set search_path = ''
as $$
  with readings as (
    select w.issued_at,
           coalesce(lead(w.issued_at) over (order by w.issued_at), 'infinity'::timestamptz) as until,
           coalesce(w.signal_level, 0) as signal,
           coalesce(w.storm_surge_m, 0) as surge
      from public.weather_alert w
     where not w.is_simulated
  ),
  days as (
    select g::date as day,
           (g::date)::timestamp at time zone 'Asia/Manila' as starts,
           (g::date + 1)::timestamp at time zone 'Asia/Manila' as ends
      from generate_series(p_from, p_to, interval '1 day') g
  )
  select d.day,
         coalesce((select max(r.signal) from readings r where r.issued_at < d.ends and r.until > d.starts), 0)::int,
         coalesce((select max(r.surge) from readings r where r.issued_at < d.ends and r.until > d.starts), 0)::real,
         (select count(*) from public.incident_report i
           where not i.is_simulated and not coalesce(i.false_report, false)
             and coalesce(i.emergency_type, i.suggested_type) = 'flood'
             and i.received_at >= d.starts and i.received_at < d.ends)::int,
         (select count(*) from public.incident_report i
           where not i.is_simulated and not coalesce(i.false_report, false)
             and coalesce(i.emergency_type, i.suggested_type) = 'fire'
             and i.received_at >= d.starts and i.received_at < d.ends)::int
    from days d
   order by d.day;
$$;

revoke all on function public.forecast_live_days(date, date) from public, anon, authenticated;
grant execute on function public.forecast_live_days(date, date) to service_role;

create or replace function public.record_forecast_run_labelled(
  p_version text,
  p_window_end date,
  p_probabilities jsonb,
  p_levels jsonb,
  p_next_index int,
  p_label text default null,
  p_simulated boolean default true
)
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  issued timestamptz := now();
  n int;
  v_label text := coalesce(
    p_version || ' ' || nullif(btrim(p_label), ''),
    p_version || ' live (sample data, replaying ' || to_char(p_window_end, 'FMDD Mon YYYY')
      || ', provisional levels)');
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
         v_label,
         coalesce(p_simulated, true)
    from public.barangay b
    left join jsonb_each_text(p_levels) v on v.key = b.name;
  get diagnostics n = row_count;
  if jsonb_typeof(p_probabilities) = 'object' then
    insert into public.forecast_run_detail (issued_at, model_version, window_end, probabilities, rule)
    values (issued, v_label, p_window_end, p_probabilities,
            coalesce((select m.model -> 'rule' from public.forecast_model m where m.is_active), '{}'::jsonb))
    on conflict (issued_at) do nothing;
  end if;
  update public.forecast_replay
     set day_index = p_next_index, last_run_at = issued, last_window_end = p_window_end
   where id;
  return n;
end $$;

revoke all on function public.record_forecast_run_labelled(text, date, jsonb, jsonb, int, text, boolean) from public, anon, authenticated;
grant execute on function public.record_forecast_run_labelled(text, date, jsonb, jsonb, int, text, boolean) to service_role;

create or replace function public.record_forecast_run(
  p_version text,
  p_window_end date,
  p_probabilities jsonb,
  p_levels jsonb,
  p_next_index int
)
returns int
language sql security definer set search_path = ''
as $$
  select public.record_forecast_run_labelled(
    p_version, p_window_end, p_probabilities, p_levels, p_next_index, null, true);
$$;
