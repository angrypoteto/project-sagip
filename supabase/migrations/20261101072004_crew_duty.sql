-- Crew duty (Joshua, 2026-11-01: "how will we know or the admin and
-- dispatcher will know who is on duty and who is active"). Decided: only
-- the crew head switches a member's duty; the assistant head may too while
-- the head is off duty (or none is named). A unit with nobody on duty is
-- not suggested for dispatch (the dashboard leaves it out; "Choose another
-- unit" still lists it). Whether duty ends on its own after a shift waits
-- for MDRRMD's shift length (plan Q51).
--
-- 1. staff.on_duty, duty_since, last_seen_at. Existing crews start on duty
--    so dispatch keeps working until their heads take over; new accounts
--    start off duty. Duty ends when the person leaves the unit, stops
--    being a responder, or is deactivated (trigger).
-- 2. set_crew_duty(): the head, or the assistant while the head is off
--    duty. Audited (dutyStarted, dutyEnded).
-- 3. update_unit_location(): stamps the sender's last_seen_at; a position
--    from someone off duty no longer moves the unit.
-- 4. unit_crew() also returns on_duty, duty_since, last_seen_at.
-- 5. Assignment pushes go to the crew on duty (to everyone on the unit
--    when nobody is, so a dispatcher's override still rings).
-- 6. Setting duty.quiet_minutes (15): on duty but no report from the phone
--    for this long is shown as "not reporting".

-- ------------------------------------------------------------------- duty

alter table public.staff
  add column on_duty boolean not null default false,
  add column duty_since timestamptz,
  add column last_seen_at timestamptz;

comment on column public.staff.on_duty is
  'Responders: on duty now. Switched by the unit''s crew head (set_crew_duty).';
comment on column public.staff.last_seen_at is
  'Responders: when their phone last sent the unit''s position.';

update public.staff
   set on_duty = true, duty_since = now()
 where role = 'responder' and unit_id is not null and deactivated_at is null;

create or replace function private.end_duty_on_leave()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.on_duty and (new.role <> 'responder' or new.deactivated_at is not null
                      or new.unit_id is null or new.unit_id is distinct from old.unit_id) then
    new.on_duty := false;
    new.duty_since := null;
  end if;
  return new;
end $$;

create trigger staff_end_duty_on_leave
  before update of unit_id, role, deactivated_at on public.staff
  for each row execute function private.end_duty_on_leave();

-- --------------------------------------------------------- audit actions

alter table public.audit_log drop constraint audit_log_action_type_check;
alter table public.audit_log add constraint audit_log_action_type_check check (action_type in (
  'verified', 'markedFalseReport', 'typeConfirmed', 'unitAssigned', 'unitReassigned',
  'statusChanged', 'resolved', 'smsCheckSent', 'contactViewed', 'settingChanged',
  'unitAdded', 'unitEdited', 'unitRetired', 'unitRestored', 'rosterChanged',
  'accountCreated', 'accountUpdated', 'accountDeactivated', 'accountReactivated',
  'passwordReset', 'residentSuspended', 'residentRestored', 'weatherSimulated',
  'alertIssued', 'alertEnded', 'reportDrafted', 'reportFinalized',
  'sosSimulated', 'reportsSimulated', 'sosCancelled', 'retentionApplied',
  'supplyUpdated', 'safePlaceSaved', 'safePlaceHidden', 'safePlaceRestored',
  'crewLeadsChanged', 'crewRequested', 'crewRequestDecided',
  'dutyStarted', 'dutyEnded'
));

-- ------------------------------------------------------------ the switch

create or replace function public.set_crew_duty(p_staff_id uuid, p_on boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me public.staff := private.require_responder();
  u public.response_unit;
  s public.staff;
begin
  if p_on is null then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select * into u from public.response_unit r where r.unit_id = me.unit_id;
  if u.unit_id is null or u.retired_at is not null
     or not (u.crew_head_id = me.id
             or (u.assistant_head_id = me.id
                 and not exists (select 1 from public.staff h
                                  where h.id = u.crew_head_id and h.on_duty))) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  select * into s from public.staff t where t.id = p_staff_id for update;
  if s.id is null or s.role <> 'responder' or s.deactivated_at is not null
     or s.unit_id is distinct from u.unit_id then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if s.on_duty = p_on then
    return;
  end if;
  update public.staff
     set on_duty = p_on, duty_since = case when p_on then now() end
   where id = s.id;
  perform private.audit_admin(me, case when p_on then 'dutyStarted' else 'dutyEnded' end,
    'staff', s.id::text, u.call_sign || ': ' || s.display_name);
end $$;

revoke all on function public.set_crew_duty(uuid, boolean) from public, anon;
grant execute on function public.set_crew_duty(uuid, boolean) to authenticated;

-- ------------------------------------------------------------- positions

create or replace function public.update_unit_location(
  p_latitude double precision,
  p_longitude double precision,
  p_captured_at timestamptz default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_responder();
  t timestamptz := private.capture_time(p_captured_at);
begin
  if p_latitude is null or p_longitude is null
     or p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  update public.staff set last_seen_at = greatest(coalesce(last_seen_at, t), t)
   where id = me.id;
  -- Someone off duty may be anywhere: their phone does not move the unit.
  if not me.on_duty then
    return;
  end if;
  update public.response_unit
     set last_latitude = p_latitude, last_longitude = p_longitude, last_location_at = t
   where unit_id = me.unit_id and (last_location_at is null or last_location_at < t);
end $$;

-- ------------------------------------------------------------------ crews

drop function public.unit_crew();
create function public.unit_crew()
returns table (
  unit_id text, staff_id uuid, display_name text, personnel_id text,
  on_duty boolean, duty_since timestamptz, last_seen_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.unit_id, s.id, s.display_name, s.personnel_id,
         s.on_duty, s.duty_since, s.last_seen_at
    from public.staff s
   where s.role = 'responder'
     and s.unit_id is not null
     and s.deactivated_at is null
     and (
       private.is_dispatcher()  -- dispatchers and admins
       or (private.current_staff_role() = 'responder'
           and s.unit_id = private.current_staff_unit())
     )
   order by s.unit_id, s.display_name;
$$;

revoke all on function public.unit_crew() from public, anon;
grant execute on function public.unit_crew() to authenticated;

-- ------------------------------------------------------------------ pushes

create or replace function private.queue_assignment_push()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  inc public.incident_report;
  v_type text;
  anyone_on boolean;
begin
  select * into inc from public.incident_report i where i.incident_id = new.incident_id;
  v_type := case coalesce(inc.emergency_type, inc.suggested_type)
              when 'flood' then 'Flood'
              when 'fire' then 'Fire'
              when 'medical' then 'Medical'
              when 'structural' then 'Structural'
              else 'Type not confirmed' end;
  select exists (select 1 from public.staff o
                  where o.role = 'responder' and o.unit_id = new.unit_id
                    and o.deactivated_at is null and o.on_duty)
    into anyone_on;
  insert into public.push_message (user_id, kind, title, body, data, status)
  select s.id, 'assignment',
         'New assignment: ' || new.incident_id,
         v_type || ' · ' || inc.barangay || ', ' || inc.district || '. Open S.A.G.I.P. to accept.',
         jsonb_build_object('type', 'assignment', 'incident_id', new.incident_id),
         private.push_status()
    from public.staff s
   where s.role = 'responder' and s.unit_id = new.unit_id and s.deactivated_at is null
     and (s.on_duty or not anyone_on);
  return new;
end $$;

-- ---------------------------------------------------------------- setting

alter table public.app_setting drop constraint app_setting_category_check;
alter table public.app_setting add constraint app_setting_category_check check (category in (
  'priority', 'reports', 'alerts', 'channels', 'contact', 'demo', 'privacy', 'inventory', 'app', 'duty'
));
insert into public.app_setting (key, category, value, min_value, max_value, description) values
  ('duty.quiet_minutes', 'duty', '15', 5, 120,
   'A crew member on duty whose phone has not reported for this many minutes is shown as not reporting');
