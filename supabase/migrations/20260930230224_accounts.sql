-- A1 Accounts (plan 7.4, FR10): admins create staff accounts, change a
-- name or role, deactivate and reactivate them, reset passwords, and
-- suspend resident accounts (abuse control). Every change is audited.
--
-- - New accounts and resets get a temporary password, returned once to the
--   admin; the person changes it on D11.
-- - A deactivated account is banned from signing in, its sessions end, and
--   every role check treats it as having no role at once.
-- - Nobody can deactivate or demote themselves, or the last active admin.
-- - A suspended resident cannot send crowd reports. An SOS still goes
--   through (FR8: life first) but arrives not account-verified, so the
--   dispatcher calls back.

alter table public.staff add column deactivated_at timestamptz;
grant select (deactivated_at) on public.staff to authenticated;
comment on column public.staff.deactivated_at is 'Set by an admin (A1); the account cannot sign in or act.';

alter table public.manila_resident add column suspended_at timestamptz;
grant select (suspended_at) on public.manila_resident to authenticated;
comment on column public.manila_resident.suspended_at is 'Set by an admin (A1): no crowd reports; SOS arrives unverified.';

alter table public.audit_log drop constraint audit_log_action_type_check;
alter table public.audit_log add constraint audit_log_action_type_check check (action_type in (
  'verified', 'markedFalseReport', 'typeConfirmed', 'unitAssigned', 'unitReassigned',
  'statusChanged', 'resolved', 'smsCheckSent', 'contactViewed', 'settingChanged',
  'unitAdded', 'unitEdited', 'unitRetired', 'unitRestored', 'rosterChanged',
  'accountCreated', 'accountUpdated', 'accountDeactivated', 'accountReactivated',
  'passwordReset', 'residentSuspended', 'residentRestored'
));

-- ------------------------------------------------------------ role checks
-- Every check now ignores deactivated accounts.

create or replace function private.current_staff_role()
returns text
language sql stable security definer set search_path = ''
as $$
  select s.role from public.staff s
   where s.id = (select auth.uid()) and s.deactivated_at is null
$$;

create or replace function private.current_staff_unit()
returns text
language sql stable security definer set search_path = ''
as $$
  select s.unit_id from public.staff s
   where s.id = (select auth.uid()) and s.deactivated_at is null
$$;

create or replace function public._require_dispatcher()
returns public.staff
language plpgsql stable security definer set search_path = ''
as $$
declare
  me public.staff;
begin
  select * into me from public.staff s
   where s.id = (select auth.uid()) and s.deactivated_at is null;
  if me.id is null or me.role not in ('dispatcher', 'admin') then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  return me;
end $$;

create or replace function private.require_responder()
returns public.staff
language plpgsql stable security definer set search_path = ''
as $$
declare
  me public.staff;
begin
  select * into me from public.staff s
   where s.id = (select auth.uid()) and s.deactivated_at is null;
  if me.id is null or me.role <> 'responder' or me.unit_id is null then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  return me;
end $$;

create or replace function private.require_admin()
returns public.staff
language plpgsql stable security definer set search_path = ''
as $$
declare
  me public.staff;
begin
  select * into me from public.staff s
   where s.id = (select auth.uid()) and s.deactivated_at is null;
  if me.id is null or me.role <> 'admin' then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  return me;
end $$;

-- set_setting and analytics_report checked the role themselves; they now
-- use require_admin (otherwise as in the configuration and analytics
-- migrations).
create or replace function public.set_setting(p_key text, p_value jsonb)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  s public.app_setting;
  v numeric;
begin
  select * into s from public.app_setting a where a.key = p_key for update;
  if s.key is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if p_value is null or jsonb_typeof(p_value) <> jsonb_typeof(s.value) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if jsonb_typeof(p_value) = 'number' then
    v := (p_value #>> '{}')::numeric;
    if (s.min_value is not null and v < s.min_value) or (s.max_value is not null and v > s.max_value) then
      raise exception 'invalid_value' using errcode = 'P0001';
    end if;
  end if;
  if (p_key = 'priority.high_at' and v > private.setting_number('priority.critical_at'))
     or (p_key = 'priority.critical_at' and v < private.setting_number('priority.high_at')) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if s.value = p_value then
    return;
  end if;
  update public.app_setting
     set value = p_value, updated_at = now(), updated_by = me.display_name
   where key = p_key;
  insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id, detail)
  values (me.id::text, me.display_name, me.role, 'settingChanged', 'app_setting', p_key,
          (s.value #>> '{}') || ' → ' || (p_value #>> '{}'));
end $$;

do $$
declare
  def text;
begin
  -- analytics_report: swap its own role check for require_admin without
  -- restating the whole report.
  select pg_get_functiondef('public.analytics_report(timestamptz, timestamptz)'::regprocedure) into def;
  def := replace(def,
    E'  select * into me from public.staff s where s.id = (select auth.uid());\n  if me.id is null or me.role <> ''admin'' then\n    raise exception ''not_allowed'' using errcode = ''P0001'';\n  end if;',
    E'  me := private.require_admin();');
  if position('private.require_admin()' in def) = 0 then
    raise exception 'analytics_report was not updated';
  end if;
  execute def;
end $$;

-- ------------------------------------------------------------ helpers

create or replace function private.temp_password()
returns text
language sql volatile set search_path = ''
as $$
  -- 12 letters and digits from 72 random bits.
  select left(translate(encode(extensions.gen_random_bytes(12), 'base64'), '+/=', 'kQz'), 12)
$$;

create or replace function private.active_admins_except(p_id uuid)
returns int
language sql stable security definer set search_path = ''
as $$
  select count(*)::int from public.staff s
   where s.role = 'admin' and s.deactivated_at is null and s.id <> p_id
$$;

-- ------------------------------------------------------------ staff accounts

create or replace function public.admin_create_staff(
  p_email text,
  p_display_name text,
  p_role text,
  p_unit_id text default null
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  email_lc text := lower(btrim(coalesce(p_email, '')));
  name text := btrim(coalesce(p_display_name, ''));
  pw text := private.temp_password();
  uid uuid := gen_random_uuid();
begin
  if email_lc !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or name = '' or length(name) > 80
     or p_role not in ('dispatcher', 'admin', 'responder')
     or (p_unit_id is not null and p_role <> 'responder') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if p_unit_id is not null and not exists (
       select 1 from public.response_unit r where r.unit_id = p_unit_id and r.retired_at is null) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if exists (select 1 from auth.users u where lower(u.email) = email_lc) then
    raise exception 'already_exists' using errcode = 'P0001';
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', email_lc,
    extensions.crypt(pw, extensions.gen_salt('bf')), now(),
    '{"provider": "email", "providers": ["email"]}',
    jsonb_build_object('display_name', name), now(), now(), '', '', '', ''
  );
  insert into auth.identities (
    id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), uid, uid::text,
    jsonb_build_object('sub', uid::text, 'email', email_lc, 'email_verified', true),
    'email', now(), now(), now()
  );
  insert into public.staff (id, display_name, email, role, unit_id)
  values (uid, name, email_lc, p_role, p_unit_id);
  perform private.audit_admin(me, 'accountCreated', 'staff', uid::text, name || ', ' || p_role);
  return jsonb_build_object('id', uid, 'temporary_password', pw);
end $$;

create or replace function public.admin_update_staff(
  p_staff_id uuid,
  p_display_name text,
  p_role text
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  s public.staff;
  name text := btrim(coalesce(p_display_name, ''));
  changes text[] := '{}';
begin
  if name = '' or length(name) > 80 or p_role not in ('dispatcher', 'admin', 'responder') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select * into s from public.staff st where st.id = p_staff_id for update;
  if s.id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if s.role <> p_role then
    if s.id = me.id then
      raise exception 'own_account' using errcode = 'P0001';
    end if;
    if s.role = 'admin' and s.deactivated_at is null and private.active_admins_except(s.id) = 0 then
      raise exception 'last_admin' using errcode = 'P0001';
    end if;
    changes := changes || ('role ' || s.role || ' → ' || p_role);
  end if;
  if s.display_name <> name then
    changes := changes || ('name ' || s.display_name || ' → ' || name);
  end if;
  if cardinality(changes) = 0 then
    return;
  end if;
  update public.staff
     set display_name = name, role = p_role,
         unit_id = case when p_role = 'responder' then unit_id else null end
   where id = s.id;
  perform private.audit_admin(me, 'accountUpdated', 'staff', s.id::text, array_to_string(changes, '; '));
end $$;

create or replace function public.admin_set_staff_active(p_staff_id uuid, p_active boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  s public.staff;
begin
  if p_active is null then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select * into s from public.staff st where st.id = p_staff_id for update;
  if s.id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if s.id = me.id then
    raise exception 'own_account' using errcode = 'P0001';
  end if;
  if (s.deactivated_at is null) = p_active then
    return;
  end if;
  if not p_active and s.role = 'admin' and private.active_admins_except(s.id) = 0 then
    raise exception 'last_admin' using errcode = 'P0001';
  end if;
  update public.staff
     set deactivated_at = case when p_active then null else now() end
   where id = s.id;
  update auth.users
     set banned_until = case when p_active then null else 'infinity'::timestamptz end,
         updated_at = now()
   where id = s.id;
  if not p_active then
    delete from auth.sessions where user_id = s.id;
  end if;
  perform private.audit_admin(me,
    case when p_active then 'accountReactivated' else 'accountDeactivated' end,
    'staff', s.id::text, s.display_name);
end $$;

create or replace function public.admin_reset_password(p_staff_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  s public.staff;
  pw text := private.temp_password();
begin
  select * into s from public.staff st where st.id = p_staff_id;
  if s.id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if s.id = me.id then
    raise exception 'own_account' using errcode = 'P0001';
  end if;
  update auth.users
     set encrypted_password = extensions.crypt(pw, extensions.gen_salt('bf')), updated_at = now()
   where id = s.id;
  delete from auth.sessions where user_id = s.id;
  perform private.audit_admin(me, 'passwordReset', 'staff', s.id::text, s.display_name);
  return jsonb_build_object('temporary_password', pw);
end $$;

-- ------------------------------------------------------------ residents

create or replace function public.admin_set_resident_suspended(p_resident_id text, p_suspended boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  r public.manila_resident;
begin
  if p_suspended is null then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select * into r from public.manila_resident m where m.manila_resident_id = p_resident_id for update;
  if r.manila_resident_id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if (r.suspended_at is not null) = p_suspended then
    return;
  end if;
  update public.manila_resident
     set suspended_at = case when p_suspended then now() else null end
   where manila_resident_id = r.manila_resident_id;
  perform private.audit_admin(me,
    case when p_suspended then 'residentSuspended' else 'residentRestored' end,
    'manila_resident', r.manila_resident_id, null);
end $$;

-- A suspended resident's crowd reports are refused; an SOS still arrives,
-- not account-verified.
create or replace function private.refuse_suspended_report()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.manila_resident_id is not null and exists (
       select 1 from public.manila_resident r
        where r.manila_resident_id = new.manila_resident_id and r.suspended_at is not null) then
    raise exception 'account_suspended' using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger crowd_report_refuse_suspended
  before insert on public.crowd_report
  for each row execute function private.refuse_suspended_report();

create or replace function private.unverify_suspended_sos()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.manila_resident_id is not null and exists (
       select 1 from public.manila_resident r
        where r.manila_resident_id = new.manila_resident_id and r.suspended_at is not null) then
    new.account_verified := false;
  end if;
  return new;
end $$;

create trigger incident_report_unverify_suspended
  before insert on public.incident_report
  for each row execute function private.unverify_suspended_sos();

-- The profile view shows the suspension (appended so readers keep working).
create or replace view public.resident_profile with (security_invoker = true) as
select
  r.manila_resident_id, r.fullname, r.contact_masked as contact_number,
  r.barangay, r.district, r.consent_given_at, r.updated_at,
  coalesce(
    (select jsonb_agg(jsonb_build_object(
        'member_id', m.member_id, 'label', m.label,
        'vulnerability_types', m.vulnerability_types, 'notes', m.notes
      ) order by m.member_id)
       from public.vulnerable_member m where m.manila_resident_id = r.manila_resident_id),
    '[]'::jsonb
  ) as household,
  r.suspended_at
from public.manila_resident r;

-- ------------------------------------------------------------ privileges

revoke execute on function
  public.admin_create_staff(text, text, text, text), public.admin_update_staff(uuid, text, text),
  public.admin_set_staff_active(uuid, boolean), public.admin_reset_password(uuid),
  public.admin_set_resident_suspended(text, boolean)
from public, anon;
grant execute on function
  public.admin_create_staff(text, text, text, text), public.admin_update_staff(uuid, text, text),
  public.admin_set_staff_active(uuid, boolean), public.admin_reset_password(uuid),
  public.admin_set_resident_suspended(text, boolean)
to authenticated;
revoke execute on function
  private.temp_password(), private.active_admins_except(uuid),
  private.refuse_suspended_report(), private.unverify_suspended_sos()
from public, anon, authenticated;
