-- Model v5's fire rule (2026-11-23, docs/OBJECTIVE-2-RESULTS.md section 14):
-- a barangay's fire is raised when it is one of the top fire places or had
-- a fire in the last 180 days. "Had a fire" reads MDRRMD's fire history
-- (loaded by hand into fire_history: barangay and date only, never from the
-- public repository) and S.A.G.I.P.'s own fire incidents.

create table public.fire_history (
  barangay text not null,
  fire_date date not null,
  source text not null default 'mdrrmd' check (source in ('mdrrmd')),
  primary key (barangay, fire_date, source)
);
comment on table public.fire_history is
  'Past fires per barangay and day (MDRRMD''s records), for the forecast''s recent-fire rule. No names, addresses, or coordinates. Read only by run-forecast through forecast_recent_fires.';

-- No policies: only the service role and security definer functions read it.
alter table public.fire_history enable row level security;
revoke all on public.fire_history from public, anon, authenticated;

create or replace function public.forecast_recent_fires(p_since date, p_to date)
returns table (barangay text)
language sql
stable
security definer
set search_path = ''
as $$
  select h.barangay
    from public.fire_history h
   where h.fire_date between p_since and p_to
  union
  select i.barangay
    from public.incident_report i
   where not i.is_simulated
     and not coalesce(i.false_report, false)
     and coalesce(i.emergency_type, i.suggested_type) = 'fire'
     and i.barangay is not null
     and (i.received_at at time zone 'Asia/Manila')::date between p_since and p_to;
$$;
revoke all on function public.forecast_recent_fires(date, date) from public, anon, authenticated;
grant execute on function public.forecast_recent_fires(date, date) to service_role;
