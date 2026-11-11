-- MDRRMD validates the crew's report and confirms the end of an incident;
-- fire stages recorded as MDRRMD records them (Joshua, 2026-11-11: "the
-- responder has an application and they will just throw it to the mdrrmd
-- and then the mdrrmd will just validate it. and then when the fire or
-- flood is done ... there is like a person who report to the mdrrmd and
-- they will confirm it"; MDRRMD's fire sheet keeps Verification, Positive
-- Alarm, 1st and 2nd Alarm, Fire Under Control, and Fire Out times).
--
-- 1. A completion report no longer closes the incident. The crew's job
--    ends (the dispatch closes and the unit is Available again), and the
--    incident shows "reported done". A dispatcher or admin validates the
--    report (correcting its figures if needed): only then is the incident
--    Resolved. Only validated reports count in the MDRRMD report.
--    Reports filed before this change already closed their incidents, so
--    they are marked validated as of their arrival.
-- 2. Fire stages: a dispatcher records each stage with its time (the
--    stage can be recorded after the fact, as MDRRMD does today). They are
--    timeline events ('fireStage', the stage in detail); recording a stage
--    again adds a later event, and the newest one counts.
-- 3. Resolving or marking false an incident frees its unit only while the
--    unit is still on that incident (after "reported done" it may be on
--    another job already).

-- ------------------------------------------------------------------ 1

alter table public.completion_report
  add column validated_at timestamptz,
  add column validated_by uuid references public.staff (id) on delete set null,
  add column validated_by_name text,
  add column corrected boolean not null default false;
comment on column public.completion_report.validated_at is
  'When MDRRMD (a dispatcher or admin) validated the crew''s report; null while it waits. Only validated reports count in the MDRRMD report.';

update public.completion_report
   set validated_at = received_at,
       validated_by_name = 'Accepted before validation (2026-11-11)'
 where validated_at is null;

create index completion_report_waiting_idx on public.completion_report (received_at)
  where validated_at is null;

alter table public.incident_report add column done_reported_at timestamptz;
comment on column public.incident_report.done_reported_at is
  'When the crew reported the job done (completion report). The incident stays open until MDRRMD validates the report or resolves it.';

alter table public.incident_event drop constraint incident_event_kind_check;
alter table public.incident_event add constraint incident_event_kind_check check (kind in (
  'received', 'smsCheckSent', 'smsReplyReceived', 'verified', 'typeConfirmed', 'assigned',
  'enRoute', 'onScene', 'resolved', 'markedFalseReport', 'cancelRequested', 'cancelWithdrawn',
  'doneReported', 'reportValidated', 'fireStage'));

alter table public.audit_log drop constraint audit_log_action_type_check;
alter table public.audit_log add constraint audit_log_action_type_check check (action_type in (
  'verified', 'markedFalseReport', 'typeConfirmed', 'unitAssigned', 'unitReassigned',
  'statusChanged', 'resolved', 'smsCheckSent', 'contactViewed', 'settingChanged', 'unitAdded',
  'unitEdited', 'unitRetired', 'unitRestored', 'rosterChanged', 'accountCreated',
  'accountUpdated', 'accountDeactivated', 'accountReactivated', 'passwordReset',
  'residentSuspended', 'residentRestored', 'weatherSimulated', 'alertIssued', 'alertEnded',
  'reportDrafted', 'reportFinalized', 'sosSimulated', 'reportsSimulated', 'sosCancelled',
  'retentionApplied', 'supplyUpdated', 'safePlaceSaved', 'safePlaceHidden',
  'safePlaceRestored', 'crewLeadsChanged', 'crewRequested', 'crewRequestDecided',
  'dutyStarted', 'dutyEnded', 'reportValidated', 'fireStageRecorded'));

-- The unit leaves an incident only while it is still on it.
create or replace function private.release_unit_from(p_unit_id text, p_incident_id text)
returns void
language sql security definer set search_path = ''
as $$
  update public.response_unit
     set status = 'available', current_incident_id = null
   where unit_id = p_unit_id
     and (current_incident_id is null or current_incident_id = p_incident_id);
$$;
revoke all on function private.release_unit_from(text, text) from public;

-- F6: the completion and damage report. The crew's job ends; the incident
-- waits for MDRRMD (validate_crew_report). Sending the same report id
-- again does nothing.
create or replace function public.submit_completion_report(
  p_report_id uuid,
  p_incident_id text,
  p_captured_at timestamptz,
  p_outcome text,
  p_persons_assisted int,
  p_time_on_scene_s int default 0,
  p_houses_damaged int default 0,
  p_injured int default 0,
  p_missing int default 0,
  p_affected_families int default 0,
  p_notes text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_responder();
  inc public.incident_report;
  t timestamptz := private.capture_time(p_captured_at);
begin
  if p_report_id is null
     or p_outcome not in ('rescued', 'treated', 'transported', 'noOneFound', 'falseReport')
     or least(p_persons_assisted, p_time_on_scene_s, p_houses_damaged, p_injured,
              p_missing, p_affected_families) < 0
     or p_persons_assisted is null
     or length(p_notes) > 1000 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.completion_report c where c.report_id = p_report_id) then
    return;
  end if;
  select * into inc from public.incident_report i where i.incident_id = p_incident_id for update;
  if inc.incident_id is null or inc.assigned_unit_id is distinct from me.unit_id then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;

  insert into public.completion_report (
    report_id, incident_id, unit_id, filed_by, captured_at, outcome, persons_assisted,
    time_on_scene_s, houses_damaged, injured, missing, affected_families, notes
  ) values (
    p_report_id, inc.incident_id, me.unit_id, me.id, t, p_outcome, p_persons_assisted,
    coalesce(p_time_on_scene_s, 0), coalesce(p_houses_damaged, 0), coalesce(p_injured, 0),
    coalesce(p_missing, 0), coalesce(p_affected_families, 0), nullif(btrim(p_notes), '')
  ) on conflict (incident_id, unit_id) do nothing;

  if inc.status <> 'resolved' and inc.done_reported_at is null then
    update public.incident_report set done_reported_at = t
     where incident_id = inc.incident_id;
    insert into public.incident_event (incident_id, kind, at, actor_name, detail)
    values (inc.incident_id, 'doneReported', t, private.call_sign(me.unit_id), p_outcome);
  end if;
  update public.dispatch set completion_time = t
   where incident_id = inc.incident_id and unit_id = me.unit_id and completion_time is null;
  perform private.release_unit_from(me.unit_id, inc.incident_id);
end $$;

-- MDRRMD validates a crew's report, correcting its figures if needed
-- (null keeps the crew's value). Resolves the incident if it is still
-- open (as a false report when the outcome says so).
create or replace function public.validate_crew_report(
  p_report_id uuid,
  p_outcome text default null,
  p_persons_assisted int default null,
  p_injured int default null,
  p_missing int default null,
  p_affected_families int default null,
  p_houses_damaged int default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  rep public.completion_report;
  inc public.incident_report;
  v_outcome text;
  v_corrected boolean;
  v_call text;
begin
  select * into rep from public.completion_report c where c.report_id = p_report_id for update;
  if rep.report_id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if rep.validated_at is not null then
    raise exception 'already_validated' using errcode = 'P0001';
  end if;
  if (p_outcome is not null
        and p_outcome not in ('rescued', 'treated', 'transported', 'noOneFound', 'falseReport'))
     or least(p_persons_assisted, p_injured, p_missing, p_affected_families, p_houses_damaged) < 0 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  v_outcome := coalesce(p_outcome, rep.outcome);
  v_corrected := v_outcome <> rep.outcome
    or coalesce(p_persons_assisted, rep.persons_assisted) <> rep.persons_assisted
    or coalesce(p_injured, rep.injured) <> rep.injured
    or coalesce(p_missing, rep.missing) <> rep.missing
    or coalesce(p_affected_families, rep.affected_families) <> rep.affected_families
    or coalesce(p_houses_damaged, rep.houses_damaged) <> rep.houses_damaged;
  update public.completion_report
     set outcome = v_outcome,
         persons_assisted = coalesce(p_persons_assisted, persons_assisted),
         injured = coalesce(p_injured, injured),
         missing = coalesce(p_missing, missing),
         affected_families = coalesce(p_affected_families, affected_families),
         houses_damaged = coalesce(p_houses_damaged, houses_damaged),
         corrected = v_corrected,
         validated_at = now(),
         validated_by = me.id,
         validated_by_name = me.display_name
   where report_id = rep.report_id;

  v_call := private.call_sign(rep.unit_id);
  insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id, detail)
  values (me.id::text, me.display_name, me.role, 'reportValidated', 'completion_report', rep.incident_id,
          v_call || case when v_corrected then ' (corrected)' else '' end);

  select * into inc from public.incident_report i where i.incident_id = rep.incident_id for update;
  insert into public.incident_event (incident_id, kind, actor_name, detail)
  values (inc.incident_id, 'reportValidated', me.display_name,
          v_call || case when v_corrected then ' (corrected)' else '' end);
  if inc.status <> 'resolved' then
    perform private.release_unit_from(rep.unit_id, inc.incident_id);
    perform public._close_dispatch(inc.incident_id);
    update public.incident_report
       set status = 'resolved', resolved_at = now(), false_report = (v_outcome = 'falseReport')
     where incident_id = inc.incident_id;
    insert into public.incident_event (incident_id, kind, actor_name, detail)
    values (inc.incident_id,
            case when v_outcome = 'falseReport' then 'markedFalseReport' else 'resolved' end,
            me.display_name, v_outcome);
  end if;
end $$;

create or replace function public.resolve_incident(p_incident_id text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  inc public.incident_report := public._open_incident(p_incident_id);
begin
  perform private.release_unit_from(inc.assigned_unit_id, inc.incident_id);
  perform public._close_dispatch(inc.incident_id);
  update public.incident_report set status = 'resolved', resolved_at = now()
   where incident_id = inc.incident_id;
  insert into public.incident_event (incident_id, kind, actor_name)
  values (inc.incident_id, 'resolved', me.display_name);
end $$;

create or replace function public.mark_false_report(p_incident_id text, p_reason text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  inc public.incident_report := public._open_incident(p_incident_id);
begin
  perform private.release_unit_from(inc.assigned_unit_id, inc.incident_id);
  perform public._close_dispatch(inc.incident_id);
  update public.incident_report
     set status = 'resolved', false_report = true, resolved_at = now()
   where incident_id = inc.incident_id;
  insert into public.incident_event (incident_id, kind, actor_name, detail)
  values (inc.incident_id, 'markedFalseReport', me.display_name, p_reason);
end $$;

-- The crew's job ends at "reported done": it leaves the phone's list and
-- no longer holds the unit.
create or replace function private.unit_incident(p_unit_id text, p_incident_id text)
returns public.incident_report
language plpgsql security definer set search_path = ''
as $$
declare
  inc public.incident_report;
begin
  select * into inc from public.incident_report i
   where i.incident_id = p_incident_id
   for update;
  if inc.incident_id is null or inc.assigned_unit_id is distinct from p_unit_id then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if inc.status = 'resolved' or inc.done_reported_at is not null then
    raise exception 'incident_closed' using errcode = 'P0001';
  end if;
  return inc;
end $$;

create or replace function public.my_assignments()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'incident_id', i.incident_id,
      'offered_at', coalesce(
        (select max(e.at) from public.incident_event e
          where e.incident_id = i.incident_id and e.kind = 'assigned'),
        i.received_at),
      'latitude', i.latitude,
      'longitude', i.longitude,
      'barangay', i.barangay,
      'district', i.district,
      'address', i.address,
      'channel', i.channel,
      'type', coalesce(i.emergency_type, i.suggested_type),
      'people_count', i.people_count,
      'resident_note', i.note,
      'vulnerable', to_jsonb(i.vulnerable),
      'status', i.status,
      'accepted_at', (select max(e.at) from public.incident_event e
                       where e.incident_id = i.incident_id and e.kind = 'enRoute'),
      'on_scene_at', (select max(e.at) from public.incident_event e
                       where e.incident_id = i.incident_id and e.kind = 'onScene'),
      'real_emergency', i.real_emergency,
      'not_real_reason', i.not_real_reason,
      'people_found', i.people_found,
      'route', (select jsonb_build_object('polyline', d.route) || coalesce(d.route_plan, '{}'::jsonb)
                  from public.dispatch d
                 where d.incident_id = i.incident_id and d.unit_id = i.assigned_unit_id
                   and d.completion_time is null and d.route is not null
                 order by d.dispatch_time desc limit 1),
      'resident_latitude', i.last_latitude,
      'resident_longitude', i.last_longitude,
      'resident_location_at', i.last_location_at,
      'cancel_requested_at', i.cancel_requested_at
    ) order by i.received_at), '[]'::jsonb)
  from public.incident_report i
  where (select private.current_staff_role()) = 'responder'
    and i.assigned_unit_id = (select private.current_staff_unit())
    and i.status in ('assigned', 'enRoute', 'onScene')
    and i.done_reported_at is null
$$;

create or replace function public.set_unit_status(
  p_status text,
  p_captured_at timestamptz default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_responder();
  open_id text;
  open_status text;
begin
  if p_status not in ('available', 'enRoute', 'onScene') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select i.incident_id, i.status into open_id, open_status
    from public.incident_report i
   where i.assigned_unit_id = me.unit_id and i.status in ('assigned', 'enRoute', 'onScene')
     and i.done_reported_at is null
   order by i.received_at desc
   limit 1;
  if p_status = 'available' then
    if open_id is not null and open_status in ('enRoute', 'onScene') then
      raise exception 'finish_report_first' using errcode = 'P0001';
    end if;
    update public.response_unit set status = 'available' where unit_id = me.unit_id;
  elsif open_id is null then
    raise exception 'no_assignment' using errcode = 'P0001';
  elsif p_status = 'enRoute' then
    if open_status = 'onScene' then
      raise exception 'already_on_scene' using errcode = 'P0001';
    end if;
    perform public.accept_assignment(open_id, p_captured_at);
  else
    perform public.mark_on_scene(open_id, p_captured_at);
  end if;
end $$;

-- F7: the unit's finished jobs, now with whether MDRRMD validated each.
create or replace function public.my_unit_history()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'incident_id', c.incident_id,
      'completed_at', c.captured_at,
      'type', coalesce(i.emergency_type, i.suggested_type),
      'barangay', i.barangay,
      'district', i.district,
      'outcome', c.outcome,
      'persons_assisted', c.persons_assisted,
      'report_delivery', 'delivered',
      'validated_at', c.validated_at
    ) order by c.captured_at desc), '[]'::jsonb)
  from (
    select * from public.completion_report r
     where r.unit_id = (select private.current_staff_unit())
     order by r.captured_at desc
     limit 200
  ) c
  join public.incident_report i on i.incident_id = c.incident_id
$$;

-- ------------------------------------------------------------------ 2

create or replace function private.fire_stages()
returns text[]
language sql immutable set search_path = ''
as $$
  select array['positiveAlarm', 'firstAlarm', 'secondAlarm', 'thirdAlarm', 'fourthAlarm',
               'fifthAlarm', 'taskForceAlpha', 'taskForceBravo', 'taskForceCharlie',
               'taskForceDelta', 'taskForceEcho', 'generalAlarm', 'fireUnderControl', 'fireOut']
$$;

create or replace function public.record_fire_stage(
  p_incident_id text,
  p_stage text,
  p_at timestamptz default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  inc public.incident_report;
  t timestamptz := coalesce(p_at, now());
begin
  select * into inc from public.incident_report i where i.incident_id = p_incident_id for update;
  if inc.incident_id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if coalesce(inc.emergency_type, inc.suggested_type) is distinct from 'fire'
     or not (p_stage = any (private.fire_stages()))
     or t > now() + interval '2 minutes'
     or t < inc.received_at - interval '12 hours' then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  insert into public.incident_event (incident_id, kind, at, actor_name, detail)
  values (inc.incident_id, 'fireStage', t, me.display_name, p_stage);
  insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id, detail)
  values (me.id::text, me.display_name, me.role, 'fireStageRecorded', 'incident_report', inc.incident_id, p_stage);
end $$;

revoke all on function public.validate_crew_report(uuid, text, int, int, int, int, int) from public, anon;
revoke all on function public.record_fire_stage(text, text, timestamptz) from public, anon;
grant execute on function public.validate_crew_report(uuid, text, int, int, int, int, int) to authenticated;
grant execute on function public.record_fire_stage(text, text, timestamptz) to authenticated;
revoke all on function private.fire_stages() from public;

-- ------------------------------------------------------------------ the board

create or replace view public.incident_board
with (security_invoker = true) as
 SELECT i.incident_id AS id,
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
    COALESCE(( SELECT array_agg(c.report_id ORDER BY c.submitted_at) AS array_agg
           FROM crowd_report c
          WHERE c.incident_id = i.incident_id), '{}'::text[]) AS crowd_report_ids,
    COALESCE(( SELECT jsonb_agg(jsonb_build_object('kind', e.kind, 'at', e.at, 'actor_name', e.actor_name, 'detail', e.detail) ORDER BY e.at, e.event_id) AS jsonb_agg
           FROM incident_event e
          WHERE e.incident_id = i.incident_id), '[]'::jsonb) AS events,
    p.score AS priority_score,
    p.severity AS priority_severity,
    p.factors AS priority_factors,
    i.is_simulated,
    i.cancel_requested_at,
    i.cancel_reason,
    i.cancel_note,
    i.cancelled,
    i.last_latitude,
    i.last_longitude,
    i.last_accuracy_m,
    i.last_location_at,
    i.updated_at,
    i.done_reported_at,
    COALESCE(( SELECT jsonb_agg(jsonb_build_object(
               'report_id', c.report_id, 'unit_id', c.unit_id, 'call_sign', u.call_sign,
               'captured_at', c.captured_at, 'outcome', c.outcome,
               'persons_assisted', c.persons_assisted, 'time_on_scene_s', c.time_on_scene_s,
               'injured', c.injured, 'missing', c.missing,
               'affected_families', c.affected_families, 'houses_damaged', c.houses_damaged,
               'notes', c.notes, 'validated_at', c.validated_at,
               'validated_by_name', c.validated_by_name, 'corrected', c.corrected)
               ORDER BY c.captured_at)
           FROM completion_report c
             LEFT JOIN response_unit u ON u.unit_id = c.unit_id
          WHERE c.incident_id = i.incident_id), '[]'::jsonb) AS crew_reports
   FROM incident_report i
     CROSS JOIN LATERAL private.priority_breakdown(i.origin, i.vulnerable, i.captured_at, i.mock_location) p(score, severity, factors);

-- A validation changes a report, not the incident: show it on the board.
create or replace function private.touch_incident_from_report_validation()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  update public.incident_report set updated_at = clock_timestamp()
   where incident_id = new.incident_id;
  return null;
end $$;

create trigger completion_report_touch_incident
  after update of validated_at on public.completion_report
  for each row execute function private.touch_incident_from_report_validation();

-- ------------------------------------------------------------------ 3. the MDRRMD report

create or replace function public.report_source(p_from timestamptz, p_to timestamptz)
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
        where e.incident_id = i.incident_id and e.kind = 'onScene') as on_scene_at,
      (select min(e.at) from public.incident_event e
        where e.incident_id = i.incident_id and e.kind = 'verified') as verified_at
    from public.incident_report i
    where i.received_at >= p_from and i.received_at < p_to and not i.is_simulated
  ),
  -- Only what MDRRMD validated counts.
  comp as (
    select c.outcome, c.persons_assisted, c.injured, c.missing, c.affected_families, c.houses_damaged
      from public.completion_report c
      join inc on inc.incident_id = c.incident_id
     where c.validated_at is not null
  ),
  -- Each fire's newest time per stage.
  stages as (
    select e.incident_id, e.detail as stage, max(e.at) as at
      from public.incident_event e
      join inc on inc.incident_id = e.incident_id and inc.type = 'fire'
     where e.kind = 'fireStage'
     group by e.incident_id, e.detail
  ),
  highest as (
    select distinct on (s.incident_id) s.incident_id, s.stage
      from stages s
     where array_position(private.fire_stages(), s.stage) <= array_position(private.fire_stages(), 'generalAlarm')
     order by s.incident_id, array_position(private.fire_stages(), s.stage) desc
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
    'reports_awaiting_validation', (
      select count(*) from public.completion_report c
        join inc on inc.incident_id = c.incident_id
       where c.validated_at is null),
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
    'fires_by_highest_alarm', coalesce(
      (select jsonb_object_agg(x.stage, x.n)
         from (select stage, count(*) as n from highest group by stage) x),
      '{}'::jsonb),
    'median_fire_out_s', (
      select percentile_cont(0.5) within group (
               order by extract(epoch from s.at - inc.verified_at)::double precision)
        from stages s join inc on inc.incident_id = s.incident_id
       where s.stage = 'fireOut' and inc.verified_at is not null and s.at >= inc.verified_at),
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
