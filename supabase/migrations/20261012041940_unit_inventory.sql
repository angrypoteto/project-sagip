-- Unit inventory, and units of other responders around Manila (the panel
-- asked for both; Joshua, 2026-10-12).
--
-- Inventory. Each unit reports what it carries: fuel and the water in its
-- tank as a share of full, and its stocks (drinking water, medical kits,
-- life vests, rescue gear) as a count against what a full load is. The
-- dashboard's Units page shows every unit's levels and flags the ones that
-- are low, so a dispatcher sees that a unit is short before sending it.
-- Only the unit's own crew changes its levels (set_unit_supply, from the
-- responder's page on the web); every change is audited.
--
-- "Low" is a level at or below the setting inventory.low_percent (30 by
-- default); "out" is zero.
--
-- This sets aside two limits of the thesis's scope, at the panel's and
-- Joshua's asking; Chapter 1 has to say so:
--   - "resource inventory tracking" was out of scope: it is now tracked,
--     per unit, as reported by the crew (no warehouse, no relief goods);
--   - units were MDRRMD's own only: fire stations, volunteer fire brigades,
--     and emergency medical stations in Manila can now be listed too, each
--     marked with whose it is (agency). A unit is only reached through the
--     app once one of its people has a responder account.

-- ------------------------------------------------------------ units

alter table public.response_unit
  add column agency text not null default 'mdrrmd'
    check (agency in ('mdrrmd', 'bfp', 'volunteer', 'ems')),
  -- Where the record comes from when it was not entered by an admin.
  add column source text check (length(source) <= 120);
comment on column public.response_unit.agency is
  'Whose unit it is: MDRRMD, the Bureau of Fire Protection, a volunteer brigade, or an emergency medical service.';

-- A crew size is not known for units listed from public records.
alter table public.response_unit alter column crew_size drop not null;

alter table public.response_unit drop constraint response_unit_unit_type_check;
alter table public.response_unit add constraint response_unit_unit_type_check
  check (unit_type in ('ambulance', 'rescueBoat', 'rescueTeam', 'fireTruck'));
comment on table public.response_unit is
  'Ambulances, rescue boats, rescue teams, and fire trucks (FR9), MDRRMD''s and other responders''.';

-- A2: the same checks as before, with fire trucks allowed.
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
     or p_unit_type is null
     or p_unit_type not in ('ambulance', 'rescueBoat', 'rescueTeam', 'fireTruck')
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
  if u.crew_size is distinct from p_crew_size then
    changes := changes || ('crew ' || coalesce(u.crew_size::text, 'not known') || ' → ' || p_crew_size);
  end if;
  if cardinality(changes) = 0 then
    return u.unit_id;
  end if;
  update public.response_unit
     set call_sign = cs, unit_type = p_unit_type, station = st, crew_size = p_crew_size
   where unit_id = u.unit_id;
  perform private.audit_admin(me, 'unitEdited', 'response_unit', u.unit_id, array_to_string(changes, '; '));
  return u.unit_id;
end $$;

-- ------------------------------------------------------------ inventory

alter table public.app_setting drop constraint app_setting_category_check;
alter table public.app_setting add constraint app_setting_category_check
  check (category in ('priority', 'reports', 'alerts', 'channels', 'contact', 'demo', 'privacy', 'inventory'));

insert into public.app_setting (key, category, value, min_value, max_value, description) values
  ('inventory.low_percent', 'inventory', '30', 5, 90,
   'A unit''s supply is shown as low at or below this share of full');

create table public.unit_supply (
  unit_id text not null references public.response_unit (unit_id) on delete cascade,
  item text not null check (item in (
    'fuel', 'tankWater', 'drinkingWater', 'medicalKits', 'lifeVests', 'rescueGear'
  )),
  -- Fuel and tank water: percent of full (capacity is 100). The stocks: how
  -- many are on board, against how many a full load is.
  quantity numeric not null check (quantity >= 0),
  capacity numeric not null check (capacity > 0),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.staff (id) on delete set null,
  updated_by_name text not null,
  primary key (unit_id, item),
  check (quantity <= capacity)
);
comment on table public.unit_supply is
  'What each unit carries, as its crew last reported it. Dispatchers and admins read all; a responder reads and changes their own unit''s.';

alter table public.unit_supply enable row level security;
create policy "unit supplies: dispatchers and admins" on public.unit_supply
  for select to authenticated using ((select private.is_dispatcher()));
create policy "unit supplies: the unit's own crew" on public.unit_supply
  for select to authenticated using (unit_id = (select private.current_staff_unit()));
grant select on public.unit_supply to authenticated;
alter publication supabase_realtime add table public.unit_supply;

alter table public.audit_log drop constraint audit_log_action_type_check;
alter table public.audit_log add constraint audit_log_action_type_check check (action_type in (
  'verified', 'markedFalseReport', 'typeConfirmed', 'unitAssigned', 'unitReassigned',
  'statusChanged', 'resolved', 'smsCheckSent', 'contactViewed', 'settingChanged',
  'unitAdded', 'unitEdited', 'unitRetired', 'unitRestored', 'rosterChanged',
  'accountCreated', 'accountUpdated', 'accountDeactivated', 'accountReactivated',
  'passwordReset', 'residentSuspended', 'residentRestored', 'weatherSimulated',
  'alertIssued', 'alertEnded', 'reportDrafted', 'reportFinalized',
  'sosSimulated', 'reportsSimulated', 'sosCancelled', 'retentionApplied',
  'supplyUpdated'
));

-- The crew reports one supply of their own unit. Fuel and tank water are
-- a percent (0 to 100); a stock is a count with what a full load is (kept
-- from the last report when left out). Responders only, for the unit they
-- are on.
create function public.set_unit_supply(
  p_item text,
  p_quantity numeric,
  p_capacity numeric default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_responder();
  v_percent boolean := p_item in ('fuel', 'tankWater');
  v_capacity numeric;
begin
  if me.unit_id is null then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if p_item is null or p_item not in (
       'fuel', 'tankWater', 'drinkingWater', 'medicalKits', 'lifeVests', 'rescueGear')
     or p_quantity is null or p_quantity < 0 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if v_percent then
    v_capacity := 100;
  else
    v_capacity := coalesce(
      p_capacity,
      (select s.capacity from public.unit_supply s where s.unit_id = me.unit_id and s.item = p_item));
    -- Whole things, at most 100,000 of them.
    if v_capacity is null or v_capacity < 1 or v_capacity > 100000
       or v_capacity <> trunc(v_capacity) or p_quantity <> trunc(p_quantity) then
      raise exception 'invalid_value' using errcode = 'P0001';
    end if;
  end if;
  if p_quantity > v_capacity then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  insert into public.unit_supply as s
    (unit_id, item, quantity, capacity, updated_at, updated_by, updated_by_name)
  values (me.unit_id, p_item, p_quantity, v_capacity, now(), me.id, me.display_name)
  on conflict (unit_id, item) do update set
    quantity = excluded.quantity, capacity = excluded.capacity,
    updated_at = now(), updated_by = excluded.updated_by,
    updated_by_name = excluded.updated_by_name;

  insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id, detail)
  values (me.id::text, me.display_name, me.role, 'supplyUpdated', 'unit_supply', me.unit_id,
          p_item || ' ' || trim_scale(p_quantity) || ' of ' || trim_scale(v_capacity));
end $$;

revoke all on function public.set_unit_supply(text, numeric, numeric) from public, anon;
grant execute on function public.set_unit_supply(text, numeric, numeric) to authenticated;
