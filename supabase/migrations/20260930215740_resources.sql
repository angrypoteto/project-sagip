-- A2 Resources (plan 7.4): units and the responder roster.
--
-- Admins add, edit, retire, and restore units, and assign responders to
-- units. A retired unit keeps its history (dispatches, completion reports)
-- but is not dispatched, and its responders are taken off it. Every change
-- is written to the audit log (FR11).

alter table public.response_unit add column retired_at timestamptz;
comment on column public.response_unit.retired_at is
  'Set when an admin retires the unit (A2); retired units are not dispatched.';

alter table public.audit_log drop constraint audit_log_action_type_check;
alter table public.audit_log add constraint audit_log_action_type_check check (action_type in (
  'verified', 'markedFalseReport', 'typeConfirmed', 'unitAssigned', 'unitReassigned',
  'statusChanged', 'resolved', 'smsCheckSent', 'contactViewed', 'settingChanged',
  'unitAdded', 'unitEdited', 'unitRetired', 'unitRestored', 'rosterChanged'
));

create or replace function private.require_admin()
returns public.staff
language plpgsql stable security definer set search_path = ''
as $$
declare
  me public.staff;
begin
  select * into me from public.staff s where s.id = (select auth.uid());
  if me.id is null or me.role <> 'admin' then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  return me;
end $$;

create or replace function private.audit_admin(
  p_me public.staff, p_action text, p_table text, p_target text, p_detail text
)
returns void
language sql security definer set search_path = ''
as $$
  insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id, detail)
  values (p_me.id::text, p_me.display_name, p_me.role, p_action, p_table, p_target, p_detail);
$$;

-- ------------------------------------------------------------ units

-- Adds a unit (p_unit_id null) or edits one. Returns the unit id.
create or replace function public.save_unit(
  p_unit_id text,
  p_call_sign text,
  p_unit_type text,
  p_station text,
  p_crew_size int
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  cs text := upper(btrim(coalesce(p_call_sign, '')));
  st text := btrim(coalesce(p_station, ''));
  u public.response_unit;
  new_id text;
  n int := 1;
  changes text[] := '{}';
begin
  if cs !~ '^[A-Z0-9][A-Z0-9-]{0,11}$'
     or p_unit_type is null or p_unit_type not in ('ambulance', 'rescueBoat', 'rescueTeam')
     or st = '' or length(st) > 80
     or p_crew_size is null or p_crew_size < 1 or p_crew_size > 50 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.response_unit r
              where upper(r.call_sign) = cs and r.unit_id is distinct from p_unit_id) then
    raise exception 'already_exists' using errcode = 'P0001';
  end if;

  if p_unit_id is null then
    new_id := 'unit-' || lower(regexp_replace(cs, '[^A-Z0-9]', '', 'g'));
    while exists (select 1 from public.response_unit r where r.unit_id = new_id) loop
      n := n + 1;
      new_id := 'unit-' || lower(regexp_replace(cs, '[^A-Z0-9]', '', 'g')) || '-' || n;
    end loop;
    insert into public.response_unit (unit_id, call_sign, unit_type, station, crew_size, status)
    values (new_id, cs, p_unit_type, st, p_crew_size, 'available');
    perform private.audit_admin(me, 'unitAdded', 'response_unit', new_id,
      cs || ', ' || p_unit_type || ', ' || st || ', crew of ' || p_crew_size);
    return new_id;
  end if;

  select * into u from public.response_unit r where r.unit_id = p_unit_id for update;
  if u.unit_id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if u.call_sign <> cs then changes := changes || ('call sign ' || u.call_sign || ' → ' || cs); end if;
  if u.unit_type <> p_unit_type then changes := changes || ('type ' || u.unit_type || ' → ' || p_unit_type); end if;
  if u.station <> st then changes := changes || ('station ' || u.station || ' → ' || st); end if;
  if u.crew_size <> p_crew_size then changes := changes || ('crew ' || u.crew_size || ' → ' || p_crew_size); end if;
  if cardinality(changes) = 0 then
    return u.unit_id;
  end if;
  update public.response_unit
     set call_sign = cs, unit_type = p_unit_type, station = st, crew_size = p_crew_size
   where unit_id = u.unit_id;
  perform private.audit_admin(me, 'unitEdited', 'response_unit', u.unit_id, array_to_string(changes, '; '));
  return u.unit_id;
end $$;

-- Takes a unit out of service. It must be free (no job, Available).
create or replace function public.retire_unit(p_unit_id text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  u public.response_unit;
  names text;
begin
  select * into u from public.response_unit r where r.unit_id = p_unit_id for update;
  if u.unit_id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if u.retired_at is not null then
    return;
  end if;
  if u.current_incident_id is not null or u.status <> 'available' then
    raise exception 'unit_not_available' using errcode = 'P0001';
  end if;
  select string_agg(s.display_name, ', ' order by s.display_name) into names
    from public.staff s where s.unit_id = u.unit_id and s.role = 'responder';
  update public.staff set unit_id = null where unit_id = u.unit_id and role = 'responder';
  update public.response_unit set retired_at = now() where unit_id = u.unit_id;
  perform private.audit_admin(me, 'unitRetired', 'response_unit', u.unit_id,
    u.call_sign || coalesce('; responders taken off: ' || names, ''));
end $$;

create or replace function public.restore_unit(p_unit_id text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  u public.response_unit;
begin
  select * into u from public.response_unit r where r.unit_id = p_unit_id for update;
  if u.unit_id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if u.retired_at is null then
    return;
  end if;
  update public.response_unit
     set retired_at = null, status = 'available', current_incident_id = null
   where unit_id = u.unit_id;
  perform private.audit_admin(me, 'unitRestored', 'response_unit', u.unit_id, u.call_sign);
end $$;

-- ------------------------------------------------------------ roster

-- Puts a responder on a unit, or takes them off (p_unit_id null).
create or replace function public.set_responder_unit(p_staff_id uuid, p_unit_id text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  s public.staff;
  u public.response_unit;
begin
  select * into s from public.staff st where st.id = p_staff_id for update;
  if s.id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if s.role <> 'responder' then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if p_unit_id is not null then
    select * into u from public.response_unit r where r.unit_id = p_unit_id;
    if u.unit_id is null then
      raise exception 'not_found' using errcode = 'P0001';
    end if;
    if u.retired_at is not null then
      raise exception 'invalid_value' using errcode = 'P0001';
    end if;
  end if;
  if s.unit_id is not distinct from p_unit_id then
    return;
  end if;
  update public.staff set unit_id = p_unit_id where id = s.id;
  perform private.audit_admin(me, 'rosterChanged', 'staff', s.id::text,
    s.display_name || ': ' || coalesce((select r.call_sign from public.response_unit r where r.unit_id = s.unit_id), 'no unit')
    || ' → ' || coalesce(u.call_sign, 'no unit'));
end $$;

-- ------------------------------------------------------------ dispatch

-- assign_unit: a retired unit is never assigned (otherwise as in the
-- routing migration).
create or replace function public.assign_unit(
  p_incident_id text,
  p_unit_id text,
  p_override_reason text default null,
  p_route jsonb default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  inc public.incident_report := public._open_incident(p_incident_id);
  u public.response_unit;
begin
  if not private.valid_route(p_route) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if inc.assigned_unit_id = p_unit_id then
    raise exception 'already_assigned' using errcode = 'P0001';
  end if;
  -- Lock the unit so two dispatchers cannot take it at the same moment.
  select * into u from public.response_unit r where r.unit_id = p_unit_id for update;
  if u.unit_id is null or u.retired_at is not null or u.status <> 'available'
     or u.current_incident_id is not null then
    raise exception 'unit_not_available' using errcode = 'P0001';
  end if;

  if inc.assigned_unit_id is not null then
    perform public._release_unit(inc.assigned_unit_id);
    perform public._close_dispatch(inc.incident_id);
  end if;

  update public.response_unit set current_incident_id = inc.incident_id where unit_id = u.unit_id;
  update public.incident_report
     set status = 'assigned',
         assigned_unit_id = u.unit_id,
         suggestion_overridden = p_override_reason is not null,
         override_reason = p_override_reason
   where incident_id = inc.incident_id;
  insert into public.dispatch (
    incident_id, unit_id, assigned_by, suggestion_overridden, override_reason, route, route_plan
  )
  values (
    inc.incident_id, u.unit_id, me.id, p_override_reason is not null, p_override_reason,
    p_route ->> 'polyline', p_route - 'polyline'
  );
  insert into public.incident_event (incident_id, kind, actor_name, detail)
  values (inc.incident_id, 'assigned', me.display_name, u.call_sign);
end $$;

revoke execute on function
  public.save_unit(text, text, text, text, int), public.retire_unit(text),
  public.restore_unit(text), public.set_responder_unit(uuid, text)
from public, anon;
grant execute on function
  public.save_unit(text, text, text, text, int), public.retire_unit(text),
  public.restore_unit(text), public.set_responder_unit(uuid, text)
to authenticated;
revoke execute on function
  private.require_admin(), private.audit_admin(public.staff, text, text, text, text)
from public, anon, authenticated;
