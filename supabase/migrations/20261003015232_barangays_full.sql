-- All 897 barangays of Manila with their boundaries (supabase/data).
--
-- The data is not in this file: it is `supabase/data/manila_barangays.json`
-- (made by `supabase/data/fetch_barangays.py` from PSA's barangay layer,
-- checked against the PSGC), loaded with `private.load_barangays(json)`.
-- See supabase/README.md, "Loading all 897 barangays".
--
-- Adds:
-- - barangay.psgc_code, the 10-digit Philippine Standard Geographic Code;
-- - manila_outline: the whole city as one shape (every barangay, plus the
--   two areas in none: Tutuban Mall and Manila North Cemetery);
-- - the "inside Manila" check (FR15) against that outline, with 50 m to
--   spare for GPS error and simplified boundaries on the bay and the river.
-- Loading changes the 10 sample rows' centers to the real ones; names stay.

alter table public.barangay add column psgc_code text unique
  check (psgc_code ~ '^13806[0-9]{5}$');
comment on table public.barangay is
  'Manila barangays: name, district (PSA sub-municipality), PSGC code, center, boundary.';

create table public.manila_outline (
  id boolean primary key default true check (id),
  boundary extensions.geography(multipolygon, 4326) not null,
  source text not null,
  loaded_at timestamptz not null default now()
);
comment on table public.manila_outline is
  'The City of Manila as one shape, from the barangay boundaries (FR15). One row.';
alter table public.manila_outline enable row level security;
-- Public geography: signed-in apps may read it; only loading changes it.
create policy "manila outline: any signed-in user" on public.manila_outline
  for select to authenticated using (true);
grant select on public.manila_outline to authenticated;

-- ------------------------------------------------------------ loading

-- An encoded polyline (precision 1e-5, the ring left open) as a closed ring.
create or replace function private.ring(p_encoded text)
returns extensions.geometry
language sql immutable set search_path = ''
as $$
  select extensions.st_addpoint(l, extensions.st_startpoint(l))
    from (select extensions.st_setsrid(
                   extensions.st_linefromencodedpolyline(p_encoded, 5), 4326) as l) s
$$;

-- [[outer, hole, ...], ...] of encoded rings as one multipolygon.
create or replace function private.shape_from_json(p_polygons jsonb)
returns extensions.geometry
language sql immutable set search_path = ''
as $$
  select extensions.st_multi(extensions.st_collectionextract(extensions.st_makevalid(
           extensions.st_collect(
             case when jsonb_array_length(poly) = 1
                  then extensions.st_makepolygon(private.ring(poly ->> 0))
                  else extensions.st_makepolygon(
                         private.ring(poly ->> 0),
                         array(select private.ring(r.v)
                                 from jsonb_array_elements_text(poly) with ordinality r(v, i)
                                where r.i > 1))
             end)), 3))
    from jsonb_array_elements(p_polygons) poly
$$;

-- Loads supabase/data/manila_barangays.json. Adds missing barangays and
-- updates the ones there (district, code, center, boundary); never removes
-- a name, since residents, reports, and forecasts refer to barangays by
-- name. Replaces the city outline. Returns how many barangays it wrote.
-- The SQL editor and the service role only.
create or replace function private.load_barangays(p_data jsonb)
returns int
language plpgsql security definer set search_path = ''
as $$
declare
  n int;
begin
  if jsonb_typeof(p_data -> 'barangays') <> 'array'
     or jsonb_array_length(p_data -> 'barangays') = 0 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  insert into public.barangay
    (name, district, psgc_code, center_latitude, center_longitude, boundary)
  select b ->> 'name', b ->> 'district', b ->> 'psgc',
         (b -> 'center' ->> 0)::double precision, (b -> 'center' ->> 1)::double precision,
         private.shape_from_json(b -> 'polygons')::extensions.geography
    from jsonb_array_elements(p_data -> 'barangays') b
  on conflict (name) do update
     set district = excluded.district,
         psgc_code = excluded.psgc_code,
         center_latitude = excluded.center_latitude,
         center_longitude = excluded.center_longitude,
         boundary = excluded.boundary;
  get diagnostics n = row_count;

  insert into public.manila_outline (id, boundary, source)
  select true,
         extensions.st_multi(extensions.st_collectionextract(extensions.st_makevalid(
           extensions.st_union(s.shape)), 3))::extensions.geography,
         coalesce(p_data ->> 'source', 'unknown')
    from (select private.shape_from_json(x -> 'polygons') as shape
            from jsonb_array_elements(p_data -> 'barangays') x
          union all
          select private.shape_from_json(x -> 'polygons')
            from jsonb_array_elements(coalesce(p_data -> 'other', '[]')) x) s
  on conflict (id) do update
     set boundary = excluded.boundary, source = excluded.source, loaded_at = now();
  return n;
end $$;

revoke all on function private.ring(text) from public, anon, authenticated;
revoke all on function private.shape_from_json(jsonb) from public, anon, authenticated;
revoke all on function private.load_barangays(jsonb) from public, anon, authenticated;
grant execute on function private.load_barangays(jsonb) to service_role;

-- ------------------------------------------------------------ FR15

-- Inside Manila City: within 50 m of the city outline once it is loaded;
-- before that, the barangay boundaries if any, else the rough box.
create or replace function private.inside_manila(p_lat double precision, p_lng double precision)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select case
    when exists (select 1 from public.manila_outline) then
      exists (
        select 1 from public.manila_outline o
         where extensions.st_dwithin(
                 o.boundary,
                 extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography,
                 50))
    when exists (select 1 from public.barangay b where b.boundary is not null) then
      exists (
        select 1 from public.barangay b
         where b.boundary is not null
           and extensions.st_covers(
                 b.boundary,
                 extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography))
    else p_lat between 14.550 and 14.640 and p_lng between 120.940 and 121.030
  end
$$;
