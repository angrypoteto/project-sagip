-- Crew duty safety nets (Joshua, 2026-11-03: "what if the head crew forget
-- to sign them in?", then "go ahead with 1 to 3"). Duty no longer depends
-- on the crew head remembering:
--
-- 1. A crew member may put themself on duty (set_crew_duty with their own
--    id and true). Ending duty stays with the head, or the assistant head
--    while the head is off duty, so a mistake is the head's to correct.
-- 2. Accepting an assignment puts the one who accepts on duty: they are
--    clearly working. Audited as dutyStarted, naming the incident.
-- 3. staff.app_open_at: the responder app checks in while it is open on
--    screen (note_app_open, no position). Someone off duty with the app in
--    use is shown as "off duty, app in use", so a forgotten member stands
--    out. unit_crew() returns it.

-- --------------------------------------------------------------- check-in

alter table public.staff add column app_open_at timestamptz;

comment on column public.staff.app_open_at is
  'Responders: when the S.A.G.I.P. app was last open on their phone (no position).';

create or replace function public.note_app_open()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me public.staff := private.require_responder();
begin
  update public.staff set app_open_at = now() where id = me.id;
end $$;

revoke all on function public.note_app_open() from public, anon;
grant execute on function public.note_app_open() to authenticated;

-- ------------------------------------------------------------- the switch

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
  lead boolean;
begin
  if p_on is null then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select * into u from public.response_unit r where r.unit_id = me.unit_id;
  if u.unit_id is null or u.retired_at is not null then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  lead := u.crew_head_id = me.id
          or (u.assistant_head_id = me.id
              and not exists (select 1 from public.staff h
                               where h.id = u.crew_head_id and h.on_duty));
  -- Anyone may start their own duty; everything else is the lead's.
  if not (coalesce(lead, false) or (p_staff_id = me.id and p_on)) then
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

-- ----------------------------------------------------------------- accept

create or replace function public.accept_assignment(p_incident_id text, p_captured_at timestamptz default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_responder();
  inc public.incident_report := private.unit_incident(me.unit_id, p_incident_id);
begin
  -- Whoever accepts is working (2026-11-03), also when a crewmate
  -- accepted first.
  if not me.on_duty then
    update public.staff set on_duty = true, duty_since = now() where id = me.id;
    perform private.audit_admin(me, 'dutyStarted', 'staff', me.id::text,
      private.call_sign(me.unit_id) || ': ' || me.display_name
        || ' (accepted ' || inc.incident_id || ')');
  end if;
  if inc.status in ('enRoute', 'onScene') then
    return;
  end if;
  update public.response_unit
     set status = 'enRoute', current_incident_id = inc.incident_id
   where unit_id = me.unit_id;
  update public.incident_report set status = 'enRoute' where incident_id = inc.incident_id;
  insert into public.incident_event (incident_id, kind, at, actor_name)
  values (inc.incident_id, 'enRoute', private.capture_time(p_captured_at), private.call_sign(me.unit_id));
end $$;

-- ------------------------------------------------------------------ crews

drop function public.unit_crew();
create function public.unit_crew()
returns table (
  unit_id text, staff_id uuid, display_name text, personnel_id text,
  on_duty boolean, duty_since timestamptz, last_seen_at timestamptz,
  app_open_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.unit_id, s.id, s.display_name, s.personnel_id,
         s.on_duty, s.duty_since, s.last_seen_at, s.app_open_at
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
