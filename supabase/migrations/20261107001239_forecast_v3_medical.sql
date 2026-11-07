-- Model v3 on MDRRMD's own records (Joshua, 2026-11-07: "we can use just
-- the mdrrmd instead and then we can lower the 72hours lead time", 48 hours
-- chosen; "Medical heatmap layer").
--
-- 1. A run is valid for the active model's own lead time (its JSON's
--    horizon_hours: 48 for lstm-kde-v3, 72 for v2 and the thesis), not a
--    fixed 72 hours. The screens read the lead time from the run's times.
-- 2. hazard_density also holds the Heatmap's Medical layer: the KDE of
--    MDRRMD's medical calls and road accidents (hazard 'medical'). It is
--    not a forecast hazard; the forecast reads only flood, fire, and
--    storm surge (shared SupabaseForecastRepository.watchDensity).

create or replace function public.record_forecast_run_labelled(
  p_version text,
  p_window_end date,
  p_probabilities jsonb,
  p_levels jsonb,
  p_next_index integer,
  p_label text default null,
  p_simulated boolean default true
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  issued timestamptz := now();
  n int;
  v_label text := coalesce(
    p_version || ' ' || nullif(btrim(p_label), ''),
    p_version || ' live (sample data, replaying ' || to_char(p_window_end, 'FMDD Mon YYYY')
      || ', provisional levels)');
  -- The active model's lead time (2026-11-07); 72 hours if it names none.
  v_hours int := coalesce(
    (select (m.model ->> 'horizon_hours')::int from public.forecast_model m where m.is_active), 72);
begin
  if p_version is null or p_window_end is null or p_next_index is null
     or jsonb_typeof(p_levels) <> 'object'
     or exists (select 1 from jsonb_each_text(p_levels) e where e.value !~ '^[lmh]{3}$') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  insert into public.barangay_forecast
    (barangay, district, issued_at, valid_until, flood_risk, fire_risk, surge_risk, model_version, is_simulated)
  select b.name, b.district, issued, issued + make_interval(hours => v_hours),
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

alter table public.hazard_density drop constraint hazard_density_hazard_check;
alter table public.hazard_density add constraint hazard_density_hazard_check
  check (hazard in ('flood', 'fire', 'stormSurge', 'medical'));
