-- Crew lists with MDRRMD personnel IDs (Joshua, 2026-10-28: "make sure
-- that their will be a list of crew on it and their full name and their
-- id"; the ID is MDRRMD's own personnel number, set by an admin).
--
-- 1. staff.personnel_id: optional; letters, digits, and dashes, up to 20,
--    stored in capitals; no two accounts share one.
-- 2. admin_set_personnel_id(): admins set or clear it (A1), audited like
--    other account changes. A separate function, so admin_create_staff and
--    admin_update_staff keep their signatures.
-- 3. unit_crew(): each unit's active responders, name and personnel ID
--    only (never email). Dispatchers and admins see every unit's crew (D7
--    Units); a responder sees only their own unit's (My unit on the web);
--    residents and anyone else see nothing. The staff table itself stays
--    readable only by its owner and admins.

alter table public.staff add column personnel_id text;

alter table public.staff add constraint staff_personnel_id_format
  check (personnel_id is null or personnel_id ~ '^[A-Z0-9][A-Z0-9-]{0,19}$');

create unique index staff_personnel_id_unique
  on public.staff (personnel_id) where personnel_id is not null;

comment on column public.staff.personnel_id is
  'MDRRMD personnel ID (employee or badge number), set by an admin on A1; shown in crew lists.';

create or replace function public.admin_set_personnel_id(p_staff_id uuid, p_personnel_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  s public.staff;
  v text := nullif(upper(btrim(coalesce(p_personnel_id, ''))), '');
begin
  if v is not null and v !~ '^[A-Z0-9][A-Z0-9-]{0,19}$' then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select * into s from public.staff st where st.id = p_staff_id for update;
  if s.id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if s.personnel_id is not distinct from v then
    return;
  end if;
  if v is not null and exists (
       select 1 from public.staff o where o.personnel_id = v and o.id <> s.id) then
    raise exception 'already_exists' using errcode = 'P0001';
  end if;
  update public.staff set personnel_id = v where id = s.id;
  perform private.audit_admin(
    me, 'accountUpdated', 'staff', s.id::text,
    'personnel ID ' || coalesce(s.personnel_id, 'none') || ' → ' || coalesce(v, 'none'));
end $$;

revoke all on function public.admin_set_personnel_id(uuid, text) from public, anon;
grant execute on function public.admin_set_personnel_id(uuid, text) to authenticated;

create or replace function public.unit_crew()
returns table (unit_id text, staff_id uuid, display_name text, personnel_id text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.unit_id, s.id, s.display_name, s.personnel_id
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
