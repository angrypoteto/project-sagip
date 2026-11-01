-- Crew heads ask only for new people (Joshua, 2026-11-01: "the crew head of
-- each unit should be able to control their own unit not with other unit
-- it should only show the new person"). A head or assistant head may ask
-- to take a member of their own unit off, or for a person with no account
-- yet; moving a responder between units stays with admins (Units page).
-- crew_candidates() listed responders on other units for that choice and
-- is dropped. Requests of the old 'add' kind already made can still be
-- decided.

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
  -- Someone from another unit is never a head's to ask for.
  if lead_unit is null or p_kind = 'add' then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  select * into me from public.staff st where st.id = (select auth.uid());
  select r.call_sign into call_sign from public.response_unit r where r.unit_id = lead_unit;
  if v_note is not null and length(v_note) > 300 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  if p_kind = 'remove' then
    select * into s from public.staff st where st.id = p_staff_id;
    if s.id is null or s.role <> 'responder' or s.deactivated_at is not null then
      raise exception 'invalid_value' using errcode = 'P0001';
    end if;
    if s.id = me.id then
      raise exception 'own_account' using errcode = 'P0001';
    end if;
    if s.unit_id is distinct from lead_unit then
      raise exception 'invalid_value' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.crew_request c
                where c.unit_id = lead_unit and c.staff_id = s.id and c.status = 'pending') then
      raise exception 'already_exists' using errcode = 'P0001';
    end if;
    insert into public.crew_request (unit_id, kind, staff_id, subject_name, note, requested_by, requested_by_name)
    values (lead_unit, 'remove', s.id, s.display_name, v_note, me.id, me.display_name)
    returning request_id into id;
    perform private.audit_admin(me, 'crewRequested', 'crew_request', id::text,
      call_sign || ': remove ' || s.display_name);
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

drop function public.crew_candidates();
