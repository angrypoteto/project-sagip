-- RLS full run (2026-11-10), check 14 "anon cannot run any private helper":
-- three functions from the crew head and crew duty migrations kept
-- Postgres's default EXECUTE for PUBLIC. Nobody signed out could reach them
-- (anon has no USAGE on the private schema), but every other private helper
-- is also closed on its own, so these are closed the same way.
--
-- - clear_unit_leads(), end_duty_on_leave(): trigger functions; nobody calls
--   them directly.
-- - current_lead_unit(): read by an RLS policy and by crew-head functions,
--   so signed-in accounts keep it, as with is_admin() and current_staff_unit().

revoke all on function private.clear_unit_leads() from public, anon, authenticated;
revoke all on function private.end_duty_on_leave() from public, anon, authenticated;
revoke all on function private.current_lead_unit() from public, anon;
grant execute on function private.current_lead_unit() to authenticated;
