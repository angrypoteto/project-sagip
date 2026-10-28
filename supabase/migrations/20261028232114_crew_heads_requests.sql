-- Crew heads and crew requests (Joshua, 2026-10-29: "the crew member head
-- is responsible for adding the new crew member ... there should be a head
-- crew on each unit so he can manage also the crew and it will just ask
-- permission to the admin"; "yes there should be an assistant head").
--
-- 1. response_unit.crew_head_id and assistant_head_id: set by admins
--    (admin_set_unit_leads), each an active responder on that unit. A lead
--    who leaves the unit, stops being a responder, or is deactivated stops
--    being its lead (trigger).
-- 2. crew_request: what a head or assistant asks for their own unit, and
--    the admin's answer. 'add': an existing responder account onto the
--    unit; 'remove': a member off it (never themself: "it will be used by
--    the other head when she or he will get replaced"); 'new': a person
--    with no account yet (name, email, personnel ID), whose account the
--    admin creates when approving. Readable by admins and by the unit's
--    own head and assistant; written only through the functions below.
-- 3. request_crew_change(), decide_crew_request() (admins; approving moves
--    the responder at once, declining needs a reason the lead sees),
--    crew_candidates() (for leads: active responders not on their unit,
--    name, personnel ID, and unit only).

-- ------------------------------------------------------------------ leads

alter table public.response_unit
  add column crew_head_id uuid references public.staff (id) on delete set null,
  add column assistant_head_id uuid references public.staff (id) on delete set null,
  add constraint response_unit_leads_differ
    check (crew_head_id is null or assistant_head_id is null or crew_head_id <> assistant_head_id);

comment on column public.response_unit.crew_head_id is
  'The unit''s crew head: asks admins to add or remove crew (crew_request).';
comment on column public.response_unit.assistant_head_id is
  'The unit''s assistant head: asks for crew changes like the head.';

create or replace function private.clear_unit_leads()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.response_unit r set crew_head_id = null
   where r.crew_head_id = new.id
     and not (new.role = 'responder' and new.deactivated_at is null and new.unit_id = r.unit_id);
  update public.response_unit r set assistant_head_id = null
   where r.assistant_head_id = new.id
     and not (new.role = 'responder' and new.deactivated_at is null and new.unit_id = r.unit_id);
  return new;
end $$;

create trigger staff_clear_unit_leads
  after update of unit_id, role, deactivated_at on public.staff
  for each row execute function private.clear_unit_leads();

-- The unit the signed-in responder leads (head or assistant), or null.
create or replace function private.current_lead_unit()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select r.unit_id
    from public.response_unit r
   where r.unit_id = private.current_staff_unit()
     and private.current_staff_role() = 'responder'
     and r.retired_at is null
     and (select auth.uid()) in (r.crew_head_id, r.assistant_head_id)
$$;

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
  'crewLeadsChanged', 'crewRequested', 'crewRequestDecided'
));

-- ------------------------------------------------------------- requests

create table public.crew_request (
  request_id uuid primary key default gen_random_uuid(),
  unit_id text not null references public.response_unit (unit_id),
  kind text not null check (kind in ('add', 'remove', 'new')),
  -- 'add' and 'remove': the responder; 'new': the account made on approval.
  staff_id uuid references public.staff (id) on delete set null,
  subject_name text not null check (length(subject_name) between 1 and 80),
  new_email text,
  new_personnel_id text,
  note text check (note is null or length(note) <= 300),
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined')),
  requested_by uuid references public.staff (id) on delete set null,
  requested_by_name text not null,
  requested_at timestamptz not null default now(),
  decided_by_name text,
  decided_at timestamptz,
  decision_note text check (decision_note is null or length(decision_note) <= 300),
  check ((kind = 'new') = (new_email is not null))
);

-- One waiting request per person and unit, and per new email.
create unique index crew_request_one_pending
  on public.crew_request (unit_id, staff_id) where status = 'pending' and staff_id is not null;
create unique index crew_request_one_pending_new
  on public.crew_request (new_email) where status = 'pending' and kind = 'new';
create index crew_request_unit on public.crew_request (unit_id, requested_at desc);

alter table public.crew_request enable row level security;
create policy "crew requests: admins, and the unit's head and assistant" on public.crew_request
  for select to authenticated
  using ((select private.is_admin()) or unit_id = (select private.current_lead_unit()));
grant select on public.crew_request to authenticated;
alter publication supabase_realtime add table public.crew_request;

-- ------------------------------------------------------------- functions

create or replace function public.admin_set_unit_leads(p_unit_id text, p_head uuid, p_assistant uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  u public.response_unit;
  old_head text;
  old_assistant text;
  new_head text;
  new_assistant text;
begin
  select * into u from public.response_unit r where r.unit_id = p_unit_id for update;
  if u.unit_id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if u.retired_at is not null or (p_head is not null and p_head = p_assistant) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if exists (
       select 1 from unnest(array[p_head, p_assistant]) as lead(id)
        where lead.id is not null and not exists (
          select 1 from public.staff s
           where s.id = lead.id and s.role = 'responder' and s.deactivated_at is null
             and s.unit_id = p_unit_id)) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if u.crew_head_id is not distinct from p_head and u.assistant_head_id is not distinct from p_assistant then
    return;
  end if;
  select display_name into old_head from public.staff where id = u.crew_head_id;
  select display_name into old_assistant from public.staff where id = u.assistant_head_id;
  select display_name into new_head from public.staff where id = p_head;
  select display_name into new_assistant from public.staff where id = p_assistant;
  update public.response_unit
     set crew_head_id = p_head, assistant_head_id = p_assistant
   where unit_id = p_unit_id;
  perform private.audit_admin(me, 'crewLeadsChanged', 'response_unit', p_unit_id,
    u.call_sign || ': head ' || coalesce(old_head, 'none') || ' → ' || coalesce(new_head, 'none')
    || '; assistant ' || coalesce(old_assistant, 'none') || ' → ' || coalesce(new_assistant, 'none'));
end $$;

create or replace function public.request_crew_change(
  p_kind text,
  p_staff_id uuid default null,
  p_name text default null,
  p_email text default null,
  p_personnel_id text default null,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  lead_unit text := private.current_lead_unit();
  me public.staff;
  s public.staff;
  call_sign text;
  v_name text := btrim(coalesce(p_name, ''));
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_pid text := nullif(upper(btrim(coalesce(p_personnel_id, ''))), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  id uuid;
begin
  if lead_unit is null then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  select * into me from public.staff st where st.id = (select auth.uid());
  select r.call_sign into call_sign from public.response_unit r where r.unit_id = lead_unit;
  if v_note is not null and length(v_note) > 300 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  if p_kind in ('add', 'remove') then
    select * into s from public.staff st where st.id = p_staff_id;
    if s.id is null or s.role <> 'responder' or s.deactivated_at is not null then
      raise exception 'invalid_value' using errcode = 'P0001';
    end if;
    if p_kind = 'remove' and s.id = me.id then
      raise exception 'own_account' using errcode = 'P0001';
    end if;
    if (p_kind = 'add' and s.unit_id is not distinct from lead_unit)
       or (p_kind = 'remove' and s.unit_id is distinct from lead_unit) then
      raise exception 'invalid_value' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.crew_request c
                where c.unit_id = lead_unit and c.staff_id = s.id and c.status = 'pending') then
      raise exception 'already_exists' using errcode = 'P0001';
    end if;
    insert into public.crew_request (unit_id, kind, staff_id, subject_name, note, requested_by, requested_by_name)
    values (lead_unit, p_kind, s.id, s.display_name, v_note, me.id, me.display_name)
    returning request_id into id;
    perform private.audit_admin(me, 'crewRequested', 'crew_request', id::text,
      call_sign || ': ' || p_kind || ' ' || s.display_name);
  elsif p_kind = 'new' then
    if v_name = '' or length(v_name) > 80
       or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
       or (v_pid is not null and v_pid !~ '^[A-Z0-9][A-Z0-9-]{0,19}$') then
      raise exception 'invalid_value' using errcode = 'P0001';
    end if;
    if exists (select 1 from auth.users u where lower(u.email) = v_email)
       or exists (select 1 from public.staff st where st.email = v_email)
       or (v_pid is not null and exists (select 1 from public.staff st where st.personnel_id = v_pid))
       or exists (select 1 from public.crew_request c
                   where c.kind = 'new' and c.status = 'pending' and c.new_email = v_email) then
      raise exception 'already_exists' using errcode = 'P0001';
    end if;
    insert into public.crew_request (unit_id, kind, subject_name, new_email, new_personnel_id, note,
                                     requested_by, requested_by_name)
    values (lead_unit, 'new', v_name, v_email, v_pid, v_note, me.id, me.display_name)
    returning request_id into id;
    perform private.audit_admin(me, 'crewRequested', 'crew_request', id::text,
      call_sign || ': new member ' || v_name);
  else
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  return id;
end $$;

-- Approving moves the responder at once (written to the audit log as a
-- roster change too); for a 'new' request the admin first creates the
-- account (admin_create_staff on the request's unit) and passes it here.
create or replace function public.decide_crew_request(
  p_request_id uuid,
  p_approve boolean,
  p_note text default null,
  p_staff_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  r public.crew_request;
  u public.response_unit;
  s public.staff;
  target text;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  select * into r from public.crew_request c where c.request_id = p_request_id for update;
  if r.request_id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if r.status <> 'pending' or (v_note is not null and length(v_note) > 300) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select * into u from public.response_unit ru where ru.unit_id = r.unit_id;

  if not p_approve then
    if v_note is null then
      raise exception 'invalid_value' using errcode = 'P0001';
    end if;
    update public.crew_request
       set status = 'declined', decided_by_name = me.display_name, decided_at = now(), decision_note = v_note
     where request_id = r.request_id;
    perform private.audit_admin(me, 'crewRequestDecided', 'crew_request', r.request_id::text,
      'declined: ' || u.call_sign || ' ' || r.kind || ' ' || r.subject_name);
    return;
  end if;

  if u.retired_at is not null then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select * into s from public.staff st
   where st.id = case when r.kind = 'new' then p_staff_id else r.staff_id end
   for update;
  if s.id is null or s.role <> 'responder' or s.deactivated_at is not null then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  target := case when r.kind = 'remove' then null else r.unit_id end;
  if r.kind = 'remove' and s.unit_id is distinct from r.unit_id then
    target := s.unit_id;  -- already off the unit: nothing to move
  end if;
  if s.unit_id is distinct from target then
    update public.staff set unit_id = target where id = s.id;
    perform private.audit_admin(me, 'rosterChanged', 'staff', s.id::text,
      s.display_name || ': '
      || coalesce((select ru.call_sign from public.response_unit ru where ru.unit_id = s.unit_id), 'no unit')
      || ' → ' || coalesce((select ru.call_sign from public.response_unit ru where ru.unit_id = target), 'no unit'));
  end if;
  if r.kind = 'new' and r.new_personnel_id is not null and s.personnel_id is null
     and not exists (select 1 from public.staff o where o.personnel_id = r.new_personnel_id) then
    update public.staff set personnel_id = r.new_personnel_id where id = s.id;
  end if;
  update public.crew_request
     set status = 'approved', staff_id = s.id, decided_by_name = me.display_name, decided_at = now(),
         decision_note = v_note
   where request_id = r.request_id;
  perform private.audit_admin(me, 'crewRequestDecided', 'crew_request', r.request_id::text,
    'approved: ' || u.call_sign || ' ' || r.kind || ' ' || r.subject_name);
end $$;

-- For a head or assistant choosing whom to ask for: active responders not
-- on their unit. Admins see the same list.
create or replace function public.crew_candidates()
returns table (staff_id uuid, display_name text, personnel_id text, unit_id text, call_sign text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id, s.display_name, s.personnel_id, s.unit_id, r.call_sign
    from public.staff s
    left join public.response_unit r on r.unit_id = s.unit_id
   where s.role = 'responder'
     and s.deactivated_at is null
     and (
       private.is_admin()
       or (private.current_lead_unit() is not null
           and s.unit_id is distinct from private.current_lead_unit())
     )
   order by s.display_name;
$$;

revoke all on function public.admin_set_unit_leads(text, uuid, uuid) from public, anon;
revoke all on function public.request_crew_change(text, uuid, text, text, text, text) from public, anon;
revoke all on function public.decide_crew_request(uuid, boolean, text, uuid) from public, anon;
revoke all on function public.crew_candidates() from public, anon;
grant execute on function public.admin_set_unit_leads(text, uuid, uuid) to authenticated;
grant execute on function public.request_crew_change(text, uuid, text, text, text, text) to authenticated;
grant execute on function public.decide_crew_request(uuid, boolean, text, uuid) to authenticated;
grant execute on function public.crew_candidates() to authenticated;
