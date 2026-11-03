-- Surge test finding 4 (NFR7, docs/SURGE-TEST.md; Joshua, 2026-11-03: "fix
-- it"). The dashboard read the whole board again on every change: with
-- 10,000 open incidents that is 10.5 MB, several times a second during a
-- surge. Now each incident carries when it last changed, and the dashboard
-- asks only for what changed since its last read (a full read once a
-- minute keeps it honest).
--
-- 1. incident_report.updated_at: set on every update of the row.
-- 2. It also moves when an event is added to the incident, and when a crowd
--    report joins or leaves it, since the board shows both.
-- 3. incident_board shows it (last column; still security_invoker), with
--    an index for "changed since".
-- None of the incident triggers acts on updated_at alone: the audit, the
-- rescue confirmation, and the Facebook post look at status, unit,
-- verification, and type changes only. The touches look incidents up by
-- key (= any(array(...)); "in (select ...)" from a transition table was
-- planned as a scan of every incident).
--
-- Checked in a rolled-back run of 10,000 SOS (with sos_open_index): 0.9 ms
-- an SOS, flat; the whole open board 10.3 MB in 0.9 s, what changed since a
-- moment before 6 rows, 7 KB, in 3 ms; a crowd report joining an incident
-- moves its stamp.

alter table public.incident_report
  add column updated_at timestamptz not null default now();

comment on column public.incident_report.updated_at is
  'When the incident, its events, or its crowd reports last changed (the dashboard reads only what changed, 2026-11-03).';

create index incident_report_updated_idx on public.incident_report (updated_at);

create or replace function private.stamp_incident_updated()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end $$;

create trigger incident_report_stamp_updated
  before update on public.incident_report
  for each row execute function private.stamp_incident_updated();

-- An event or a crowd report changes what the board shows for its incident.
create or replace function private.touch_incidents_from_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.incident_report i set updated_at = clock_timestamp()
   where i.incident_id = any (array(select distinct n.incident_id from new_rows n where n.incident_id is not null))
     -- A row this transaction already wrote is stamped already (an SOS
     -- adds its incident and its first event together).
     and i.xmin <> pg_current_xact_id()::xid;
  return null;
end $$;

create trigger incident_event_touch_incident
  after insert on public.incident_event
  referencing new table as new_rows
  for each statement execute function private.touch_incidents_from_events();

create or replace function private.touch_incidents_from_reports()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Only the reports whose incident changed (a transition table cannot be
  -- limited to one column).
  update public.incident_report i set updated_at = clock_timestamp()
   where i.incident_id = any (array(
     select x.id
       from new_rows n join old_rows o on o.report_id = n.report_id
       cross join lateral (values (n.incident_id), (o.incident_id)) x(id)
      where n.incident_id is distinct from o.incident_id and x.id is not null))
     and i.xmin <> pg_current_xact_id()::xid;
  return null;
end $$;

create trigger crowd_report_touch_incident
  after update on public.crowd_report
  referencing new table as new_rows old table as old_rows
  for each statement execute function private.touch_incidents_from_reports();

revoke all on function private.stamp_incident_updated() from public, anon, authenticated;
revoke all on function private.touch_incidents_from_events() from public, anon, authenticated;
revoke all on function private.touch_incidents_from_reports() from public, anon, authenticated;

create or replace view public.incident_board
with (security_invoker = true) as
 select i.incident_id as id,
    i.origin,
    i.channel,
    i.status,
    i.suggested_type,
    i.emergency_type,
    i.latitude,
    i.longitude,
    i.barangay,
    i.district,
    i.address,
    i.accuracy_m,
    i.captured_at,
    i.received_at,
    i.manila_resident_id,
    i.people_count,
    i.note,
    i.vulnerable,
    i.account_verified,
    i.mock_location,
    i.verification_method,
    i.assigned_unit_id,
    i.suggestion_overridden,
    i.override_reason,
    i.false_report,
    i.resolved_at,
    coalesce((select array_agg(c.report_id order by c.submitted_at)
                from public.crowd_report c
               where c.incident_id = i.incident_id), '{}'::text[]) as crowd_report_ids,
    coalesce((select jsonb_agg(jsonb_build_object('kind', e.kind, 'at', e.at, 'actor_name', e.actor_name,
                                                  'detail', e.detail) order by e.at, e.event_id)
                from public.incident_event e
               where e.incident_id = i.incident_id), '[]'::jsonb) as events,
    p.score as priority_score,
    p.severity as priority_severity,
    p.factors as priority_factors,
    i.is_simulated,
    i.cancel_requested_at,
    i.cancel_reason,
    i.cancel_note,
    i.cancelled,
    i.last_latitude,
    i.last_longitude,
    i.last_accuracy_m,
    i.last_location_at,
    i.updated_at
   from public.incident_report i
     cross join lateral private.priority_breakdown(i.origin, i.vulnerable, i.captured_at, i.mock_location)
       p(score, severity, factors);
