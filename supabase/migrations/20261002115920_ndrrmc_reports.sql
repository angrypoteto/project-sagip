-- NDRRMC reports (A5, A6; Objective 4; thesis Process 5.0, data store D8).
--
-- An administrator picks a period; report_source() returns the figures for
-- the incidents received in it (counts only: no names, numbers, addresses,
-- or coordinates), the dashboard drafts the sections from them, and the
-- administrator reviews, edits, and saves the report here. A new draft
-- keeps the figures as they were when it was made. A final report cannot
-- be changed. Drafting and finalizing are audited.
--
-- The text is put together from the figures with fixed wording for now
-- (method 'assembled'); the RAG engine (plan 10.6) will write it later
-- from the same figures (method 'rag').
--
-- Everything here is added; the audit log only gains two action types.

alter table public.audit_log drop constraint audit_log_action_type_check;
alter table public.audit_log add constraint audit_log_action_type_check check (action_type in (
  'verified', 'markedFalseReport', 'typeConfirmed', 'unitAssigned', 'unitReassigned',
  'statusChanged', 'resolved', 'smsCheckSent', 'contactViewed', 'settingChanged',
  'unitAdded', 'unitEdited', 'unitRetired', 'unitRestored', 'rosterChanged',
  'accountCreated', 'accountUpdated', 'accountDeactivated', 'accountReactivated',
  'passwordReset', 'residentSuspended', 'residentRestored', 'weatherSimulated',
  'alertIssued', 'alertEnded', 'reportDrafted', 'reportFinalized'
));

create sequence public.ndrrmc_report_number_seq start 1;
revoke all on sequence public.ndrrmc_report_number_seq from anon, authenticated;

create table public.ndrrmc_report (
  report_id text primary key
    default ('RPT-' || lpad(nextval('public.ndrrmc_report_number_seq')::text, 4, '0')),
  period_start timestamptz not null,
  period_end timestamptz not null,
  title text not null check (length(btrim(title)) between 1 and 160),
  status text not null default 'draft' check (status in ('draft', 'final')),
  method text not null default 'assembled' check (method in ('assembled', 'rag')),
  -- The figures the draft was written from, as report_source() gave them.
  source jsonb not null,
  -- [{"key": ..., "title": ..., "body": ...}] in the order of the report.
  sections jsonb not null check (jsonb_typeof(sections) = 'array'),
  -- How long collecting the records and drafting took (Objective 4).
  generation_ms int check (generation_ms >= 0),
  created_by uuid references public.staff (id) on delete set null,
  created_by_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  finalized_at timestamptz,
  finalized_by_name text,
  check (period_end > period_start)
);
comment on table public.ndrrmc_report is 'NDRRMC report drafts and final reports (Objective 4). Admins only.';

alter table public.ndrrmc_report enable row level security;
revoke all on public.ndrrmc_report from anon, authenticated;
create policy "ndrrmc reports: admins" on public.ndrrmc_report
  for select to authenticated using ((select private.is_admin()));
grant select on public.ndrrmc_report to authenticated;
alter publication supabase_realtime add table public.ndrrmc_report;

-- The figures for incidents received in [p_from, p_to). The same
-- definitions as buildReportSource() in packages/shared (the mock).
create function public.report_source(p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  result jsonb;
begin
  perform private.require_admin();
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '400 days' then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  with inc as (
    select
      i.incident_id, i.origin, i.status, i.false_report, i.vulnerable,
      coalesce(i.emergency_type, i.suggested_type) as type,
      i.barangay, i.district, i.received_at,
      (select min(e.at) from public.incident_event e
        where e.incident_id = i.incident_id and e.kind = 'assigned') as assigned_at,
      (select min(e.at) from public.incident_event e
        where e.incident_id = i.incident_id and e.kind = 'onScene') as on_scene_at
    from public.incident_report i
    where i.received_at >= p_from and i.received_at < p_to
  ),
  comp as (
    select c.outcome, c.persons_assisted, c.injured, c.missing, c.affected_families, c.houses_damaged
      from public.completion_report c
      join inc on inc.incident_id = c.incident_id
  ),
  disp as (
    select d.unit_id from public.dispatch d join inc on inc.incident_id = d.incident_id
  ),
  alerts as (
    select a.is_simulated from public.public_alert a
     where a.issued_at >= p_from and a.issued_at < p_to
  ),
  weather as (
    select w.signal_level, w.rainfall_intensity, w.storm_surge_m, w.is_simulated
      from public.weather_alert w
     where w.issued_at >= p_from and w.issued_at < p_to
  )
  select jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'incidents', (select count(*) from inc),
    'sos', (select count(*) from inc where origin = 'sos'),
    'clusters', (select count(*) from inc where origin = 'crowdCluster'),
    'resolved', (select count(*) from inc where status = 'resolved' and not false_report),
    'open', (select count(*) from inc where status <> 'resolved'),
    'false_reports', (select count(*) from inc where false_report),
    'vulnerable_incidents', (select count(*) from inc where cardinality(vulnerable) > 0),
    'by_type', coalesce(
      (select jsonb_agg(jsonb_build_object('type', x.type, 'count', x.n)
                order by x.n desc, x.type nulls last)
         from (select type, count(*) as n from inc group by type) x),
      '[]'::jsonb),
    'by_barangay', coalesce(
      (select jsonb_agg(jsonb_build_object('barangay', x.barangay, 'district', x.district, 'count', x.n)
                order by x.n desc, x.barangay)
         from (select barangay, min(district) as district, count(*) as n from inc group by barangay) x),
      '[]'::jsonb),
    'completion_reports', (select count(*) from comp),
    'resolved_without_report', (
      select count(*) from inc
       where inc.status = 'resolved' and not inc.false_report
         and not exists (select 1 from public.completion_report c where c.incident_id = inc.incident_id)),
    'persons_assisted', (select coalesce(sum(persons_assisted), 0) from comp),
    'injured', (select coalesce(sum(injured), 0) from comp),
    'missing', (select coalesce(sum(missing), 0) from comp),
    'affected_families', (select coalesce(sum(affected_families), 0) from comp),
    'houses_damaged', (select coalesce(sum(houses_damaged), 0) from comp),
    'outcomes', coalesce(
      (select jsonb_object_agg(x.outcome, x.n)
         from (select outcome, count(*) as n from comp group by outcome) x),
      '{}'::jsonb),
    'dispatches', (select count(*) from disp),
    'units_deployed', (select count(distinct unit_id) from disp),
    'median_dispatch_s', (
      select percentile_cont(0.5) within group (
               order by extract(epoch from assigned_at - received_at)::double precision)
        from inc),
    'median_response_s', (
      select percentile_cont(0.5) within group (
               order by extract(epoch from on_scene_at - received_at)::double precision)
        from inc),
    'alerts_issued', (select count(*) from alerts),
    'alerts_simulated', (select count(*) from alerts where is_simulated),
    'max_signal', (select max(signal_level) from weather),
    'max_rainfall', (select max(rainfall_intensity) from weather),
    'max_surge_m', (select max(storm_surge_m) from weather),
    'weather_simulated', (select coalesce(bool_or(is_simulated), false) from weather)
  ) into result;
  return result;
end $$;

-- Text an administrator may save: a title, and 1 to 12 sections, each with
-- a key, a title, and a body of at most 6,000 characters.
create function private.report_text_ok(p_title text, p_sections jsonb)
returns boolean
language sql immutable set search_path = ''
as $$
  -- CASE, so the array functions never see something that is not an array.
  select case
    when p_sections is null or jsonb_typeof(p_sections) <> 'array' then false
    else length(btrim(coalesce(p_title, ''))) between 1 and 160
     and jsonb_array_length(p_sections) between 1 and 12
     and not exists (
       select 1 from jsonb_array_elements(p_sections) s
        where case
                when jsonb_typeof(s) <> 'object' then true
                else coalesce(s ->> 'key', '') = ''
                  or length(btrim(coalesce(s ->> 'title', ''))) not between 1 and 120
                  or jsonb_typeof(s -> 'body') is distinct from 'string'
                  or length(s ->> 'body') > 6000
              end)
  end
$$;

-- Saves a new draft (p_report_id null) for a period, or the edited text of
-- an existing draft. Returns the report id.
create function public.save_ndrrmc_report(
  p_report_id text,
  p_from timestamptz,
  p_to timestamptz,
  p_title text,
  p_sections jsonb,
  p_generation_ms int default null
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  r public.ndrrmc_report;
  new_id text;
begin
  if not private.report_text_ok(p_title, p_sections)
     or (p_generation_ms is not null and p_generation_ms < 0) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  if p_report_id is null then
    insert into public.ndrrmc_report (
      period_start, period_end, title, source, sections, generation_ms,
      created_by, created_by_name
    ) values (
      p_from, p_to, btrim(p_title), public.report_source(p_from, p_to), p_sections,
      p_generation_ms, me.id, me.display_name
    ) returning report_id into new_id;
    perform private.audit_admin(me, 'reportDrafted', 'ndrrmc_report', new_id, btrim(p_title));
    return new_id;
  end if;

  select * into r from public.ndrrmc_report where report_id = p_report_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if r.status = 'final' then
    raise exception 'already_final' using errcode = 'P0001';
  end if;
  update public.ndrrmc_report
     set title = btrim(p_title), sections = p_sections, updated_at = now()
   where report_id = p_report_id;
  return p_report_id;
end $$;

create function public.finalize_ndrrmc_report(p_report_id text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  r public.ndrrmc_report;
begin
  select * into r from public.ndrrmc_report where report_id = p_report_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if r.status = 'final' then
    raise exception 'already_final' using errcode = 'P0001';
  end if;
  update public.ndrrmc_report
     set status = 'final', finalized_at = now(), finalized_by_name = me.display_name,
         updated_at = now()
   where report_id = p_report_id;
  perform private.audit_admin(me, 'reportFinalized', 'ndrrmc_report', p_report_id, r.title);
end $$;

revoke execute on function private.report_text_ok(text, jsonb) from public, anon, authenticated;
revoke execute on function
  public.report_source(timestamptz, timestamptz),
  public.save_ndrrmc_report(text, timestamptz, timestamptz, text, jsonb, int),
  public.finalize_ndrrmc_report(text)
from public, anon;
grant execute on function
  public.report_source(timestamptz, timestamptz),
  public.save_ndrrmc_report(text, timestamptz, timestamptz, text, jsonb, int),
  public.finalize_ndrrmc_report(text)
to authenticated;
