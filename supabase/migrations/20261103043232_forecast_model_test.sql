-- FR4 (Joshua, 2026-11-03: "make the system now 100%"): D8 shows the
-- model's tested RMSE and confusion-matrix accuracy next to each forecast.
-- The figures are in the active model's own file (`test`, written by
-- ml/forecast/heatmap/export_live.py: per hazard the test windows, how many
-- had an incident, accuracy, precision, recall, F1, RMSE, and the accuracy
-- of always answering the majority). forecast_model has no read policy, so
-- this function hands out only those figures, to dispatchers and admins.

create or replace function public.forecast_model_test()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when private.is_dispatcher() then (
    select jsonb_build_object(
             'version', m.version,
             'trained_on', m.model -> 'trained_on',
             'data', m.model -> 'data',
             'test', m.model -> 'test')
      from public.forecast_model m
     where m.is_active and m.model ? 'test'
     limit 1)
  end;
$$;

revoke all on function public.forecast_model_test() from public, anon;
grant execute on function public.forecast_model_test() to authenticated;
