-- Safe places (Joshua, 2026-10-19): the nearest place that suits the
-- emergency. It brings back, in a new form, the "nearest evacuation center"
-- that was dropped on 2026-10-11 (plan Q38; thesis Table 3.1 item 7).
--
-- What suits which emergency (provisional, for MDRRMD to confirm; the same
-- rules are in packages/shared/lib/src/models/safe_place.dart):
--   flood       somewhere high: an evacuation center, a school, a barangay
--               hall, a covered court. Never open ground (it floods first).
--   fire        open ground: an evacuation center, a basketball court, a
--               covered court, a park or plaza, a school ground; at least
--               300 m from the fire.
--   structural  open ground away from buildings: an evacuation center, a
--               basketball court, a park or plaza; at least 100 m away.
--   medical     a hospital.
-- For every emergency, a place within 150 m of a confirmed open flood or
-- 300 m of a confirmed open fire is left out (the same confirmed incidents
-- road_hazards() gives the responders' routes).
--
-- The places: 763 from OpenStreetMap (supabase/data/manila_safe_places.sql,
-- made by supabase/data/fetch_safe_places.py), plus what an admin adds on
-- A2 (MDRRMD's own evacuation centers, marked official). An admin can hide
-- a wrong place; nothing is deleted. No capacity or occupancy: evacuation
-- center management stays out of scope (CLAUDE.md).
--
-- Who sees what: any signed-in user reads the places that are not hidden;
-- dispatchers and admins also read hidden ones; only admins change them,
-- through the functions below, and every change is in the audit log (FR11).
-- safe_places_near() never says where the confirmed incidents are: a
-- resident only learns that a place was left out, not why.

alter table public.audit_log drop constraint audit_log_action_type_check;
alter table public.audit_log add constraint audit_log_action_type_check check (action_type in (
  'verified', 'markedFalseReport', 'typeConfirmed', 'unitAssigned', 'unitReassigned',
  'statusChanged', 'resolved', 'smsCheckSent', 'contactViewed', 'settingChanged',
  'unitAdded', 'unitEdited', 'unitRetired', 'unitRestored', 'rosterChanged',
  'accountCreated', 'accountUpdated', 'accountDeactivated', 'accountReactivated',
  'passwordReset', 'residentSuspended', 'residentRestored', 'weatherSimulated',
  'alertIssued', 'alertEnded', 'reportDrafted', 'reportFinalized',
  'sosSimulated', 'reportsSimulated', 'sosCancelled', 'retentionApplied',
  'supplyUpdated', 'safePlaceSaved', 'safePlaceHidden', 'safePlaceRestored'
));

create table public.safe_place (
  place_id text primary key check (place_id ~ '^(osm-[nwr][0-9]+|adm-[0-9a-f]{10})$'),
  name text check (name is null or (name = btrim(name) and char_length(name) between 1 and 120)),
  kind text not null check (kind in (
    'evacuationCenter', 'school', 'barangayHall', 'coveredCourt',
    'basketballCourt', 'openSpace', 'hospital')),
  latitude double precision not null check (latitude between 14.4 and 14.8),
  longitude double precision not null check (longitude between 120.8 and 121.2),
  barangay text,
  district text,
  official boolean not null default false,
  hidden_at timestamptz,
  source text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.staff (id) on delete set null
);
comment on table public.safe_place is
  'Places that can serve as a safe place in an emergency (OpenStreetMap, and evacuation centers an admin adds). No capacity: not evacuation center management.';
comment on column public.safe_place.official is
  'An evacuation center MDRRMD designated (entered by an admin), not only a place on the map.';
comment on column public.safe_place.updated_by is
  'The admin who last changed the row; null for a row as loaded from OpenStreetMap (reloading refreshes only those).';

alter table public.safe_place enable row level security;
create policy "safe places: signed-in users read the visible ones; staff all" on public.safe_place
  for select to authenticated
  using (hidden_at is null or (select private.is_dispatcher()));
grant select on public.safe_place to authenticated;

-- ------------------------------------------------------------ the rules

-- The kinds of place that suit an emergency; empty for anything else.
create function private.safe_kinds(p_need text)
returns text[]
language sql immutable set search_path = ''
as $$
  select case p_need
    when 'flood' then array['evacuationCenter', 'school', 'barangayHall', 'coveredCourt']
    when 'fire' then array['evacuationCenter', 'basketballCourt', 'coveredCourt', 'openSpace', 'school']
    when 'structural' then array['evacuationCenter', 'basketballCourt', 'openSpace']
    when 'medical' then array['hospital']
    else array[]::text[]
  end
$$;

-- How far a place must be from the emergency itself, in meters.
create function private.safe_min_meters(p_need text)
returns double precision
language sql immutable set search_path = ''
as $$
  select case p_need when 'fire' then 300 when 'structural' then 100 else 0 end::double precision
$$;

-- The nearest places that suit [p_need] from a position, nearest first,
-- with the straight-line distance. Places near a confirmed open flood or
-- fire are left out; nothing about those incidents is returned.
create function public.safe_places_near(
  p_latitude double precision,
  p_longitude double precision,
  p_need text,
  p_limit int default 3
)
returns table (
  place_id text, name text, kind text, latitude double precision,
  longitude double precision, barangay text, district text,
  official boolean, meters double precision
)
language plpgsql stable security definer set search_path = ''
as $$
declare
  here extensions.geography;
begin
  if (select auth.uid()) is null then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if p_latitude is null or p_longitude is null
     or p_latitude not between -90 and 90 or p_longitude not between -180 and 180
     or cardinality(private.safe_kinds(p_need)) = 0
     or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  here := extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography;
  return query
    with hazards as (
      select coalesce(i.emergency_type, i.suggested_type) as type,
             extensions.st_setsrid(extensions.st_makepoint(i.longitude, i.latitude), 4326)::extensions.geography as at
        from public.incident_report i
       where coalesce(i.emergency_type, i.suggested_type) in ('flood', 'fire')
         and (i.verification_method is not null or i.origin = 'crowdCluster')
         and i.status <> 'resolved'
         and not i.false_report
         and not i.cancelled
         and i.latitude is not null and i.longitude is not null
    ), places as (
      select s.*,
             extensions.st_setsrid(extensions.st_makepoint(s.longitude, s.latitude), 4326)::extensions.geography as at
        from public.safe_place s
       where s.hidden_at is null
         and s.kind = any (private.safe_kinds(p_need))
    )
    select p.place_id, p.name, p.kind, p.latitude, p.longitude, p.barangay,
           p.district, p.official, extensions.st_distance(p.at, here)
      from places p
     where extensions.st_distance(p.at, here) >= private.safe_min_meters(p_need)
       and not exists (
         select 1 from hazards h
          where extensions.st_dwithin(p.at, h.at, case h.type when 'fire' then 300 else 150 end))
     order by extensions.st_distance(p.at, here), p.place_id
     limit p_limit;
end $$;

comment on function public.safe_places_near(double precision, double precision, text, int) is
  'The nearest safe places that suit the emergency (flood, fire, structural, medical); any signed-in user.';

-- ------------------------------------------------------------ admin (A2)

-- Adds a place (p_place_id null) or edits one; returns its id. The place
-- must be in Manila; its barangay is worked out from the position.
create function public.save_safe_place(
  p_place_id text,
  p_name text,
  p_kind text,
  p_latitude double precision,
  p_longitude double precision,
  p_official boolean
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  nm text := nullif(btrim(coalesce(p_name, '')), '');
  s public.safe_place;
  brgy text;
  dist text;
  new_id text;
  changes text[] := '{}';
begin
  if p_kind is null or p_kind not in (
       'evacuationCenter', 'school', 'barangayHall', 'coveredCourt',
       'basketballCourt', 'openSpace', 'hospital')
     or char_length(coalesce(nm, '')) > 120
     or p_latitude is null or p_longitude is null
     or p_latitude not between 14.4 and 14.8 or p_longitude not between 120.8 and 121.2
     or p_official is null then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if not private.inside_manila(p_latitude, p_longitude) then
    raise exception 'outside_manila' using errcode = 'P0001';
  end if;
  -- An evacuation center is the department's own: it needs a name.
  if p_kind = 'evacuationCenter' and nm is null then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select b.name, b.district into brgy, dist from private.barangay_at(p_latitude, p_longitude) b;

  if p_place_id is null then
    loop
      new_id := 'adm-' || substr(md5(gen_random_uuid()::text), 1, 10);
      exit when not exists (select 1 from public.safe_place x where x.place_id = new_id);
    end loop;
    insert into public.safe_place
      (place_id, name, kind, latitude, longitude, barangay, district, official, source, updated_by)
    values
      (new_id, nm, p_kind, p_latitude, p_longitude, brgy, dist, p_official, 'Added by an administrator', me.id);
    perform private.audit_admin(me, 'safePlaceSaved', 'safe_place', new_id,
      'added ' || coalesce(nm, p_kind) || ', ' || p_kind || ', ' || coalesce(brgy, '?')
      || case when p_official then ', official evacuation center' else '' end);
    return new_id;
  end if;

  select * into s from public.safe_place x where x.place_id = p_place_id for update;
  if s.place_id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if s.name is distinct from nm then changes := changes || ('name ' || coalesce(s.name, '(none)') || ' → ' || coalesce(nm, '(none)')); end if;
  if s.kind <> p_kind then changes := changes || ('kind ' || s.kind || ' → ' || p_kind); end if;
  if (s.latitude, s.longitude) is distinct from (p_latitude, p_longitude) then
    changes := changes || ('moved to ' || coalesce(brgy, '?'));
  end if;
  if s.official <> p_official then changes := changes || ('official ' || s.official || ' → ' || p_official); end if;
  if cardinality(changes) = 0 then
    return s.place_id;
  end if;
  update public.safe_place
     set name = nm, kind = p_kind, latitude = p_latitude, longitude = p_longitude,
         barangay = brgy, district = dist, official = p_official,
         updated_at = now(), updated_by = me.id
   where place_id = s.place_id;
  perform private.audit_admin(me, 'safePlaceSaved', 'safe_place', s.place_id, array_to_string(changes, '; '));
  return s.place_id;
end $$;

-- Hides a place (a wrong one: private, closed, not safe) or shows it again.
create function public.set_safe_place_hidden(p_place_id text, p_hidden boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  s public.safe_place;
begin
  if p_hidden is null then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select * into s from public.safe_place x where x.place_id = p_place_id for update;
  if s.place_id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if (s.hidden_at is not null) = p_hidden then
    return;
  end if;
  update public.safe_place
     set hidden_at = case when p_hidden then now() end, updated_at = now(), updated_by = me.id
   where place_id = s.place_id;
  perform private.audit_admin(me,
    case when p_hidden then 'safePlaceHidden' else 'safePlaceRestored' end,
    'safe_place', s.place_id, coalesce(s.name, s.kind) || coalesce(', ' || s.barangay, ''));
end $$;

revoke execute on function
  private.safe_kinds(text), private.safe_min_meters(text)
  from public, anon, authenticated;
revoke execute on function
  public.safe_places_near(double precision, double precision, text, int),
  public.save_safe_place(text, text, text, double precision, double precision, boolean),
  public.set_safe_place_hidden(text, boolean)
  from public, anon;
grant execute on function
  public.safe_places_near(double precision, double precision, text, int),
  public.save_safe_place(text, text, text, double precision, double precision, boolean),
  public.set_safe_place_hidden(text, boolean)
  to authenticated;

-- Realtime: the dashboard's layer and A2 follow changes.
alter publication supabase_realtime add table public.safe_place;
