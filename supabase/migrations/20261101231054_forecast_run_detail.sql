-- Why a barangay is low, moderate, or high (Joshua, 2026-11-02: "when i
-- clicked the baranggay it should show here the history of the barangay why
-- it is low, meduim, or high"). A level comes from two numbers and a rule:
-- the LSTM's chance of at least one incident of the hazard in Manila in the
-- next 72 hours, and the barangay's KDE density of past incidents
-- (hazard_density). record_forecast_run kept only the levels; it now also
-- keeps each run's three chances and the rule in force, so D8's barangay
-- panel can say which part of the rule gave the level.

create table public.forecast_run_detail (
  issued_at timestamptz primary key,
  model_version text not null,
  window_end date,
  -- {"flood": 0.11, "fire": 0.66, "storm_surge": 0.0}
  probabilities jsonb not null,
  -- The model's rule (plan Q22): {"high": {...}, "moderate": [...]}
  rule jsonb not null
);
comment on table public.forecast_run_detail is
  'Each forecast run''s chance per hazard and the rule that made the levels (D8 explanation).';

alter table public.forecast_run_detail enable row level security;
grant select on public.forecast_run_detail to authenticated;
create policy "forecast run detail: dispatchers and admins" on public.forecast_run_detail
  for select to authenticated
  using ((select private.is_dispatcher()));

create or replace function public.record_forecast_run(
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
  if jsonb_typeof(p_probabilities) = 'object' then
    insert into public.forecast_run_detail (issued_at, model_version, window_end, probabilities, rule)
    values (issued, p_version, p_window_end, p_probabilities,
            coalesce((select m.model -> 'rule' from public.forecast_model m where m.is_active), '{}'::jsonb))
    on conflict (issued_at) do nothing;
  end if;
  update public.forecast_replay
     set day_index = p_next_index, last_run_at = issued, last_window_end = p_window_end
   where id;
  return n;
end $$;
