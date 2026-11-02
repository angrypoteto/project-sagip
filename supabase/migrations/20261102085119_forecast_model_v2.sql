-- The live forecast's model trained on the recorded 2021 to 2026 data
-- (Joshua, 2026-11-02: live weather, with the model trained on the data we
-- collected; export_live.py --variant recorded writes forecast_live_v2.json).
-- It has flood and fire only (there is no storm surge record to learn from)
-- and no replay days (run-forecast feeds it the last 14 days of live
-- weather), so the loader now asks for flood and fire, and lets days and
-- weather be empty as long as they match.

create or replace function private.load_forecast_model(p_model jsonb)
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
     or not (p_model -> 'hazards' ?& array['flood', 'fire']) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  update public.forecast_model set is_active = false where is_active and version <> v;
  insert into public.forecast_model (version, model, is_active)
  values (v, p_model, true)
  on conflict (version) do update set model = excluded.model, is_active = true, loaded_at = now();
  update public.forecast_replay set day_index = null where id;
  return v || ': ' || (select string_agg(k, ', ' order by k) from jsonb_object_keys(p_model -> 'hazards') k)
    || ', ' || jsonb_array_length(p_model -> 'days') || ' replay days';
end $$;

revoke all on function private.load_forecast_model(jsonb) from public, anon, authenticated;
grant execute on function private.load_forecast_model(jsonb) to service_role;
