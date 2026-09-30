-- Mobile app backend, part 2: the checked functions the phones call.
--
-- Same rules as the dispatcher actions: clients never write tables; each
-- function checks the caller first. Records made on a phone carry the
-- phone's id (client UUID) and capture time, so a record sent twice after a
-- reconnect is stored once and keeps the time it was made (NFR1, Q31).
--
-- New error codes the app maps to friendly text (besides not_allowed,
-- incident_closed, invalid_value, not_found):
--   outside_manila, rate_limited, no_location     (crowd reports, FR15)
--   no_assignment, finish_report_first, already_on_scene   (unit status, FR9)

-- ------------------------------------------------------------ helpers

create or replace function private.require_resident()
returns public.manila_resident
language plpgsql stable security definer set search_path = ''
as $$
declare
  me public.manila_resident;
begin
  select * into me from public.manila_resident r where r.auth_user_id = (select auth.uid());
  if me.manila_resident_id is null then
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
  select * into me from public.staff s where s.id = (select auth.uid());
  if me.id is null or me.role <> 'responder' or me.unit_id is null then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  return me;
end $$;

-- The phone's capture time, never in the future.
create or replace function private.capture_time(p timestamptz)
returns timestamptz
language sql stable set search_path = ''
as $$ select least(coalesce(p, now()), now()) $$;

-- Last ten digits of a Philippine mobile number: '0917 000 4821',
-- '+639170004821', and '639170004821' all give '9170004821'.
create or replace function private.phone_key(p text)
returns text
language sql immutable set search_path = ''
as $$ select right(regexp_replace(coalesce(p, ''), '\D', '', 'g'), 10) $$;

-- FR15: inside Manila City. Uses barangay boundaries once they are loaded;
-- until then the same rough box the app uses.
create or replace function private.inside_manila(p_lat double precision, p_lng double precision)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select case
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

create or replace function private.call_sign(p_unit_id text)
returns text
language sql stable security definer set search_path = ''
as $$ select u.call_sign from public.response_unit u where u.unit_id = p_unit_id $$;

-- The incident assigned to this unit, locked for update.
create or replace function private.unit_incident(p_unit_id text, p_incident_id text)
returns public.incident_report
language plpgsql security definer set search_path = ''
as $$
declare
  inc public.incident_report;
begin
  select * into inc from public.incident_report i
   where i.incident_id = p_incident_id
   for update;
  if inc.incident_id is null or inc.assigned_unit_id is distinct from p_unit_id then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if inc.status = 'resolved' then
    raise exception 'incident_closed' using errcode = 'P0001';
  end if;
  return inc;
end $$;

-- ------------------------------------------------------------ resident account

-- After phone sign-in: the resident record for this number. Links a record
-- MDRRMD created before the app (same verified number, not yet linked).
-- Returns null when the number has no record.
create or replace function public.link_resident()
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  key text;
  rid text;
begin
  if uid is null then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  select r.manila_resident_id into rid from public.manila_resident r where r.auth_user_id = uid;
  if rid is not null then
    return rid;
  end if;
  select private.phone_key(u.phone) into key from auth.users u where u.id = uid;
  if key is null or length(key) <> 10 then
    return null;
  end if;
  update public.manila_resident r
     set auth_user_id = uid, updated_at = now()
   where r.manila_resident_id = (
     select r2.manila_resident_id from public.manila_resident r2
      where r2.auth_user_id is null and private.phone_key(r2.contact_number) = key
      order by r2.manila_resident_id
      limit 1)
  returning r.manila_resident_id into rid;
  return rid;
end $$;

-- S4: creates the resident record for a verified number. If the number
-- already has one, returns it (the app treats that as a sign-in).
create or replace function public.register_resident(p_fullname text, p_barangay text, p_district text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  rid text;
  key text;
  known public.barangay;
begin
  if uid is null or exists (select 1 from public.staff s where s.id = uid) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  rid := public.link_resident();
  if rid is not null then
    return rid;
  end if;
  select private.phone_key(u.phone) into key from auth.users u where u.id = uid;
  if key is null or length(key) <> 10 then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if coalesce(length(btrim(p_fullname)), 0) = 0 or length(p_fullname) > 120
     or coalesce(length(btrim(p_barangay)), 0) = 0
     or coalesce(length(btrim(p_district)), 0) = 0 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select * into known from public.barangay b where b.name = btrim(p_barangay);
  insert into public.manila_resident (auth_user_id, fullname, contact_number, barangay, district)
  values (uid, btrim(p_fullname), '0' || key, btrim(p_barangay), coalesce(known.district, btrim(p_district)))
  returning manila_resident_id into rid;
  return rid;
end $$;

-- S7: asks MDRRMD to delete the resident's data (RA 10173). One open
-- request at a time.
create or replace function public.request_data_deletion()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.manila_resident := private.require_resident();
begin
  if not exists (
    select 1 from public.data_deletion_request d
     where d.manila_resident_id = me.manila_resident_id and d.handled_at is null
  ) then
    insert into public.data_deletion_request (manila_resident_id) values (me.manila_resident_id);
  end if;
end $$;

-- ------------------------------------------------------------ vulnerability profile

create or replace function public.give_consent()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.manila_resident := private.require_resident();
begin
  update public.manila_resident
     set consent_given_at = coalesce(consent_given_at, now()), updated_at = now()
   where manila_resident_id = me.manila_resident_id;
end $$;

-- No profile may be kept without consent (NFR4), so the household goes too.
create or replace function public.withdraw_consent()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.manila_resident := private.require_resident();
begin
  delete from public.vulnerable_member where manila_resident_id = me.manila_resident_id;
  update public.manila_resident
     set consent_given_at = null, updated_at = now()
   where manila_resident_id = me.manila_resident_id;
end $$;

-- R11: adds a member (no id) or updates one. Returns the member id.
create or replace function public.save_vulnerable_member(
  p_member_id bigint,
  p_label text,
  p_types text[],
  p_notes text default null
)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  me public.manila_resident := private.require_resident();
  mid bigint;
begin
  if me.consent_given_at is null then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if coalesce(length(btrim(p_label)), 0) = 0 or length(p_label) > 80
     or coalesce(cardinality(p_types), 0) = 0
     or not (p_types <@ array['seniorCitizen', 'pwd', 'pregnant', 'other'])
     or length(p_notes) > 200 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if p_member_id is null then
    insert into public.vulnerable_member (manila_resident_id, label, vulnerability_types, notes)
    values (me.manila_resident_id, btrim(p_label), p_types, nullif(btrim(p_notes), ''))
    returning member_id into mid;
  else
    update public.vulnerable_member
       set label = btrim(p_label), vulnerability_types = p_types, notes = nullif(btrim(p_notes), '')
     where member_id = p_member_id and manila_resident_id = me.manila_resident_id
    returning member_id into mid;
    if mid is null then
      raise exception 'not_found' using errcode = 'P0001';
    end if;
  end if;
  update public.manila_resident set updated_at = now() where manila_resident_id = me.manila_resident_id;
  return mid;
end $$;

create or replace function public.remove_vulnerable_member(p_member_id bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.manila_resident := private.require_resident();
  mid bigint;
begin
  delete from public.vulnerable_member
   where member_id = p_member_id and manila_resident_id = me.manila_resident_id
  returning member_id into mid;
  if mid is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  update public.manila_resident set updated_at = now() where manila_resident_id = me.manila_resident_id;
end $$;

-- Household members now carry their id, so R11 can edit them.
create or replace view public.resident_profile with (security_invoker = true) as
select
  r.manila_resident_id, r.fullname, r.contact_masked as contact_number,
  r.barangay, r.district, r.consent_given_at, r.updated_at,
  coalesce(
    (select jsonb_agg(jsonb_build_object(
        'member_id', m.member_id,
        'label', m.label, 'vulnerability_types', m.vulnerability_types, 'notes', m.notes
      ) order by m.member_id)
       from public.vulnerable_member m where m.manila_resident_id = r.manila_resident_id),
    '[]'::jsonb
  ) as household
from public.manila_resident r;

-- ------------------------------------------------------------ SOS

-- R1: an SOS from the app. It appears on the Triage Queue at once as
-- Pending Verification (FR8). Sending the same client UUID again returns
-- the same incident. With no GPS fix at all, the barangay's centre is used
-- and the accuracy is left empty; the dispatcher calls back for the spot.
create or replace function public.submit_sos(
  p_client_uuid uuid,
  p_captured_at timestamptz,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_accuracy_m double precision default null,
  p_barangay text default null,
  p_district text default null,
  p_mock_location boolean default false
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  me public.manila_resident := private.require_resident();
  existing public.incident_report;
  lat double precision := p_latitude;
  lng double precision := p_longitude;
  brgy text := coalesce(nullif(btrim(p_barangay), ''), me.barangay);
  dist text := coalesce(nullif(btrim(p_district), ''), me.district);
  vuln text[] := '{}';
  new_id text;
begin
  if p_client_uuid is null or (p_latitude is null) <> (p_longitude is null) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if p_latitude is not null
     and (p_latitude not between -90 and 90 or p_longitude not between -180 and 180) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  select * into existing from public.incident_report i where i.client_uuid = p_client_uuid;
  if existing.incident_id is not null then
    if existing.manila_resident_id is distinct from me.manila_resident_id then
      raise exception 'not_allowed' using errcode = 'P0001';
    end if;
    return existing.incident_id;
  end if;

  if lat is null then
    select b.center_latitude, b.center_longitude into lat, lng
      from public.barangay b where b.name = brgy;
    lat := coalesce(lat, 14.5995);
    lng := coalesce(lng, 120.9842);
  end if;

  -- Vulnerable household types raise priority (FR2), only with consent.
  if me.consent_given_at is not null then
    select coalesce(array_agg(distinct t order by t), '{}') into vuln
      from public.vulnerable_member m, unnest(m.vulnerability_types) t
     where m.manila_resident_id = me.manila_resident_id;
  end if;

  begin
    insert into public.incident_report (
      client_uuid, origin, channel, status, latitude, longitude, barangay, district,
      accuracy_m, captured_at, received_at, manila_resident_id, vulnerable,
      account_verified, mock_location
    ) values (
      p_client_uuid, 'sos', 'app', 'pendingVerification', lat, lng, brgy, dist,
      case when p_latitude is null then null else p_accuracy_m end,
      private.capture_time(p_captured_at), now(), me.manila_resident_id, vuln,
      true, coalesce(p_mock_location, false)
    ) returning incident_id into new_id;
  exception when unique_violation then
    -- The same SOS arrived by another path at the same moment.
    select i.incident_id into new_id from public.incident_report i where i.client_uuid = p_client_uuid;
    return new_id;
  end;
  insert into public.incident_event (incident_id, kind) values (new_id, 'received');
  return new_id;
end $$;

-- R2: optional details added after sending.
create or replace function public.add_sos_details(
  p_client_uuid uuid,
  p_type text default null,
  p_people_count int default null,
  p_needs_extra_help boolean default false,
  p_note text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.manila_resident := private.require_resident();
  inc public.incident_report;
begin
  select * into inc from public.incident_report i
   where i.client_uuid = p_client_uuid and i.manila_resident_id = me.manila_resident_id
   for update;
  if inc.incident_id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if inc.status = 'resolved' then
    raise exception 'incident_closed' using errcode = 'P0001';
  end if;
  if (p_type is not null and p_type not in ('flood', 'fire', 'medical', 'structural'))
     or p_people_count < 1 or length(p_note) > 500 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  update public.incident_report
     set suggested_type = coalesce(p_type, suggested_type),
         people_count = p_people_count,
         needs_extra_help = coalesce(p_needs_extra_help, false),
         note = nullif(btrim(p_note), '')
   where incident_id = inc.incident_id;
end $$;

-- R2, R3, R6: the resident's SOS requests in the app's SosRequest shape,
-- newest first, with the assigned unit and its last position while the
-- rescue is under way. The mock-location flag is never shown to residents.
create or replace function public.my_sos()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(x.row order by x.captured_at desc), '[]'::jsonb)
  from (
    select i.captured_at, jsonb_build_object(
      'client_id', coalesce(i.client_uuid::text, i.incident_id),
      'captured_at', i.captured_at,
      'delivery', 'delivered',
      'latitude', i.latitude,
      'longitude', i.longitude,
      'accuracy_m', i.accuracy_m,
      'barangay', i.barangay,
      'district', i.district,
      'details', jsonb_build_object(
        'type', i.suggested_type,
        'people_count', i.people_count,
        'needs_extra_help', i.needs_extra_help,
        'note', i.note),
      'sent_via', i.channel,
      'sent_at', i.received_at,
      'delivered_at', i.received_at,
      'incident_id', i.incident_id,
      'status', i.status,
      'status_times', coalesce((
        select jsonb_object_agg(s.status, s.at)
          from (
            select case e.kind
                     when 'received' then 'pendingVerification'
                     when 'verified' then 'confirmed'
                     when 'assigned' then 'assigned'
                     when 'enRoute' then 'enRoute'
                     when 'onScene' then 'onScene'
                     when 'resolved' then 'resolved'
                     when 'markedFalseReport' then 'resolved'
                   end as status,
                   max(e.at) as at
              from public.incident_event e
             where e.incident_id = i.incident_id
             group by 1
          ) s
         where s.status is not null), '{}'::jsonb),
      'unit_call_sign', u.call_sign,
      'unit_type', u.unit_type,
      'responder_latitude', case when i.status in ('assigned', 'enRoute', 'onScene') then u.last_latitude end,
      'responder_longitude', case when i.status in ('assigned', 'enRoute', 'onScene') then u.last_longitude end,
      'responder_location_at', case when i.status in ('assigned', 'enRoute', 'onScene') then u.last_location_at end
    ) as row
    from public.incident_report i
    left join public.response_unit u on u.unit_id = i.assigned_unit_id
    where i.origin = 'sos'
      and i.manila_resident_id = (select private.current_resident_id())
  ) x
$$;

-- ------------------------------------------------------------ crowd reports

-- R4: a hazard report. Checks FR15 on the server too: inside Manila and at
-- most 5 reports an hour (provisional until MDRRMD sets it in A3), counted
-- by capture time, plus a hard cap of 10 received per hour so back-dated
-- capture times cannot get around it. DBSCAN runs in the insert trigger.
create or replace function public.submit_crowd_report(
  p_client_uuid uuid,
  p_captured_at timestamptz,
  p_description text,
  p_type text default null,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_accuracy_m double precision default null,
  p_barangay text default null,
  p_district text default null
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  me public.manila_resident := private.require_resident();
  t timestamptz := private.capture_time(p_captured_at);
  existing public.crowd_report;
  new_id text;
begin
  if p_client_uuid is null
     or coalesce(length(btrim(p_description)), 0) = 0 or length(p_description) > 500
     or (p_type is not null and p_type not in ('flood', 'fire', 'medical', 'structural')) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  select * into existing from public.crowd_report c where c.client_uuid = p_client_uuid;
  if existing.report_id is not null then
    if existing.manila_resident_id is distinct from me.manila_resident_id then
      raise exception 'not_allowed' using errcode = 'P0001';
    end if;
    return existing.report_id;
  end if;

  if p_latitude is null or p_longitude is null then
    raise exception 'no_location' using errcode = 'P0001';
  end if;
  if not private.inside_manila(p_latitude, p_longitude) then
    raise exception 'outside_manila' using errcode = 'P0001';
  end if;
  if (select count(*) from public.crowd_report c
       where c.manila_resident_id = me.manila_resident_id
         and c.captured_at > t - interval '1 hour' and c.captured_at <= t) >= 5
     or (select count(*) from public.crowd_report c
          where c.manila_resident_id = me.manila_resident_id
            and c.submitted_at > now() - interval '1 hour') >= 10 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  begin
    insert into public.crowd_report (
      client_uuid, manila_resident_id, description, reported_type,
      latitude, longitude, accuracy_m, barangay, district, source, captured_at
    ) values (
      p_client_uuid, me.manila_resident_id, btrim(p_description), p_type,
      p_latitude, p_longitude, p_accuracy_m,
      coalesce(nullif(btrim(p_barangay), ''), me.barangay),
      case when nullif(btrim(p_barangay), '') is null then me.district
           else coalesce(nullif(btrim(p_district), ''), me.district) end,
      'app', t
    ) returning report_id into new_id;
  exception when unique_violation then
    select c.report_id into new_id from public.crowd_report c where c.client_uuid = p_client_uuid;
  end;
  return new_id;
end $$;

-- R6: the resident's reports in the app's HazardReport shape with their
-- stage: Checking (DBSCAN still looking), Confirmed (part of an incident),
-- Resolved, or Not confirmed (no one else reported it within the hour).
create or replace function public.my_crowd_reports()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(x.row order by x.captured_at desc), '[]'::jsonb)
  from (
    select c.captured_at, jsonb_build_object(
      'client_id', coalesce(c.client_uuid::text, c.report_id),
      'captured_at', c.captured_at,
      'description', c.description,
      'type', coalesce(c.reported_type, c.category),
      'latitude', c.latitude,
      'longitude', c.longitude,
      'accuracy_m', c.accuracy_m,
      'barangay', c.barangay,
      'district', c.district,
      'delivery', 'delivered',
      'delivered_at', c.submitted_at,
      'server_id', c.report_id,
      'stage', case
                 when i.incident_id is not null and i.status = 'resolved' then 'resolved'
                 when i.incident_id is not null then 'confirmed'
                 when c.captured_at < now() - interval '60 minutes' then 'notConfirmed'
                 else 'checking'
               end,
      'incident_id', c.incident_id
    ) as row
    from public.crowd_report c
    left join public.incident_report i on i.incident_id = c.incident_id
    where c.manila_resident_id = (select private.current_resident_id())
    order by c.captured_at desc
    limit 200
  ) x
$$;

-- DBSCAN now uses the capture time (reports made offline count from when
-- they were made) and falls back to the resident's chosen type when the
-- classifier has not suggested one yet.
create or replace function public.recluster_crowd_reports()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  c record;
  new_id text;
begin
  for c in
    with recent as (
      select r.report_id, r.incident_id, coalesce(r.category, r.reported_type) as category,
             r.latitude, r.longitude, r.barangay, r.district, r.source, r.captured_at,
             extensions.st_clusterdbscan(
               extensions.st_transform(
                 extensions.st_setsrid(extensions.st_makepoint(r.longitude, r.latitude), 4326),
                 32651
               ),
               50, 3
             ) over () as cluster_id
        from public.crowd_report r
       where r.captured_at > now() - interval '60 minutes'
    )
    select cluster_id,
           array_agg(report_id order by captured_at) as report_ids,
           (array_agg(incident_id order by captured_at) filter (where incident_id is not null))[1] as incident_id,
           mode() within group (order by category) filter (where category is not null) as category,
           avg(latitude) as latitude,
           avg(longitude) as longitude,
           min(captured_at) as first_at,
           (array_agg(barangay order by captured_at))[1] as barangay,
           (array_agg(district order by captured_at))[1] as district,
           (array_agg(source order by captured_at))[1] as source
      from recent
     where cluster_id is not null
     group by cluster_id
  loop
    if c.incident_id is null then
      insert into public.incident_report (
        origin, channel, status, suggested_type, latitude, longitude,
        barangay, district, captured_at, received_at
      ) values (
        'crowdCluster', c.source, 'confirmed', c.category, c.latitude, c.longitude,
        c.barangay, c.district, c.first_at, now()
      ) returning incident_id into new_id;
      insert into public.incident_event (incident_id, kind) values (new_id, 'received');
      update public.crowd_report set incident_id = new_id where report_id = any (c.report_ids);
    else
      update public.crowd_report set incident_id = c.incident_id
       where report_id = any (c.report_ids) and incident_id is null;
    end if;
  end loop;
  return null;
end $$;

-- ------------------------------------------------------------ responder

-- F2: accept and start. The unit and incident go En route.
create or replace function public.accept_assignment(p_incident_id text, p_captured_at timestamptz default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_responder();
  inc public.incident_report := private.unit_incident(me.unit_id, p_incident_id);
begin
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

-- F4 Arrived, F3 Mark on scene.
create or replace function public.mark_on_scene(p_incident_id text, p_captured_at timestamptz default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_responder();
  inc public.incident_report := private.unit_incident(me.unit_id, p_incident_id);
  t timestamptz := private.capture_time(p_captured_at);
begin
  if inc.status = 'onScene' then
    return;
  end if;
  update public.response_unit
     set status = 'onScene', current_incident_id = inc.incident_id
   where unit_id = me.unit_id;
  update public.incident_report set status = 'onScene' where incident_id = inc.incident_id;
  update public.dispatch set arrival_time = t
   where incident_id = inc.incident_id and unit_id = me.unit_id and arrival_time is null;
  insert into public.incident_event (incident_id, kind, at, actor_name)
  values (inc.incident_id, 'onScene', t, private.call_sign(me.unit_id));
end $$;

-- F5: the on-scene check (FR8). A real emergency counts as verified on
-- scene if no dispatcher verified it; "not real" needs a reason.
create or replace function public.confirm_on_scene(
  p_incident_id text,
  p_real_emergency boolean,
  p_reason text default null,
  p_people_found int default null,
  p_captured_at timestamptz default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_responder();
  inc public.incident_report := private.unit_incident(me.unit_id, p_incident_id);
begin
  if inc.status <> 'onScene' or p_real_emergency is null or p_people_found < 0
     or (not p_real_emergency and coalesce(length(btrim(p_reason)), 0) = 0) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  update public.incident_report
     set real_emergency = p_real_emergency,
         not_real_reason = case when p_real_emergency then null else btrim(p_reason) end,
         people_found = p_people_found,
         verification_method = case
           when p_real_emergency and verification_method is null then 'onScene'
           else verification_method end
   where incident_id = inc.incident_id;
  if p_real_emergency and inc.verification_method is null then
    insert into public.incident_event (incident_id, kind, at, actor_name, detail)
    values (inc.incident_id, 'verified', private.capture_time(p_captured_at),
            private.call_sign(me.unit_id), 'onScene');
  end if;
end $$;

-- F1: the status control (FR9). Available only after the completion report;
-- En route and On scene need an assignment.
create or replace function public.set_unit_status(p_status text, p_captured_at timestamptz default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_responder();
  open_id text;
  open_status text;
begin
  if p_status not in ('available', 'enRoute', 'onScene') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select i.incident_id, i.status into open_id, open_status
    from public.incident_report i
   where i.assigned_unit_id = me.unit_id and i.status in ('assigned', 'enRoute', 'onScene')
   order by i.received_at desc
   limit 1;
  if p_status = 'available' then
    if open_id is not null and open_status in ('enRoute', 'onScene') then
      raise exception 'finish_report_first' using errcode = 'P0001';
    end if;
    update public.response_unit set status = 'available' where unit_id = me.unit_id;
  elsif open_id is null then
    raise exception 'no_assignment' using errcode = 'P0001';
  elsif p_status = 'enRoute' then
    if open_status = 'onScene' then
      raise exception 'already_on_scene' using errcode = 'P0001';
    end if;
    perform public.accept_assignment(open_id, p_captured_at);
  else
    perform public.mark_on_scene(open_id, p_captured_at);
  end if;
end $$;

-- F6: the completion and damage report. Resolves the incident (as a false
-- report when the outcome says so), closes the dispatch, and frees the
-- unit. Sending the same report id again does nothing.
create or replace function public.submit_completion_report(
  p_report_id uuid,
  p_incident_id text,
  p_captured_at timestamptz,
  p_outcome text,
  p_persons_assisted int,
  p_time_on_scene_s int default 0,
  p_houses_damaged int default 0,
  p_injured int default 0,
  p_missing int default 0,
  p_affected_families int default 0,
  p_notes text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_responder();
  inc public.incident_report;
  t timestamptz := private.capture_time(p_captured_at);
begin
  if p_report_id is null
     or p_outcome not in ('rescued', 'treated', 'transported', 'noOneFound', 'falseReport')
     or least(p_persons_assisted, p_time_on_scene_s, p_houses_damaged, p_injured,
              p_missing, p_affected_families) < 0
     or p_persons_assisted is null
     or length(p_notes) > 1000 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.completion_report c where c.report_id = p_report_id) then
    return;
  end if;
  select * into inc from public.incident_report i where i.incident_id = p_incident_id for update;
  if inc.incident_id is null or inc.assigned_unit_id is distinct from me.unit_id then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;

  insert into public.completion_report (
    report_id, incident_id, unit_id, filed_by, captured_at, outcome, persons_assisted,
    time_on_scene_s, houses_damaged, injured, missing, affected_families, notes
  ) values (
    p_report_id, inc.incident_id, me.unit_id, me.id, t, p_outcome, p_persons_assisted,
    coalesce(p_time_on_scene_s, 0), coalesce(p_houses_damaged, 0), coalesce(p_injured, 0),
    coalesce(p_missing, 0), coalesce(p_affected_families, 0), nullif(btrim(p_notes), '')
  ) on conflict (incident_id, unit_id) do nothing;

  if inc.status <> 'resolved' then
    update public.incident_report
       set status = 'resolved', resolved_at = t, false_report = (p_outcome = 'falseReport')
     where incident_id = inc.incident_id;
    insert into public.incident_event (incident_id, kind, at, actor_name, detail)
    values (inc.incident_id,
            case when p_outcome = 'falseReport' then 'markedFalseReport' else 'resolved' end,
            t, private.call_sign(me.unit_id), p_outcome);
  end if;
  update public.dispatch set completion_time = t
   where incident_id = inc.incident_id and unit_id = me.unit_id and completion_time is null;
  update public.response_unit
     set status = 'available', current_incident_id = null
   where unit_id = me.unit_id
     and (current_incident_id is null or current_incident_id = inc.incident_id);
end $$;

-- Position sharing (FR9). Older positions than the last one are ignored,
-- so positions sent late after a reconnect do not move the unit backwards.
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
  update public.response_unit
     set last_latitude = p_latitude, last_longitude = p_longitude, last_location_at = t
   where unit_id = me.unit_id and (last_location_at is null or last_location_at < t);
end $$;

-- F1 to F5: this unit's open assignments in the app's Assignment shape.
-- 'assigned' is an offer; 'enRoute' and 'onScene' are the current job.
-- Vulnerability types only, never names (plan Q9).
create or replace function public.my_assignments()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'incident_id', i.incident_id,
      'offered_at', coalesce(
        (select max(e.at) from public.incident_event e
          where e.incident_id = i.incident_id and e.kind = 'assigned'),
        i.received_at),
      'latitude', i.latitude,
      'longitude', i.longitude,
      'barangay', i.barangay,
      'district', i.district,
      'address', i.address,
      'channel', i.channel,
      'type', coalesce(i.emergency_type, i.suggested_type),
      'people_count', i.people_count,
      'resident_note', i.note,
      'vulnerable', to_jsonb(i.vulnerable),
      'status', i.status,
      'accepted_at', (select max(e.at) from public.incident_event e
                       where e.incident_id = i.incident_id and e.kind = 'enRoute'),
      'on_scene_at', (select max(e.at) from public.incident_event e
                       where e.incident_id = i.incident_id and e.kind = 'onScene'),
      'real_emergency', i.real_emergency,
      'not_real_reason', i.not_real_reason,
      'people_found', i.people_found
    ) order by i.received_at), '[]'::jsonb)
  from public.incident_report i
  where (select private.current_staff_role()) = 'responder'
    and i.assigned_unit_id = (select private.current_staff_unit())
    and i.status in ('assigned', 'enRoute', 'onScene')
$$;

-- F7: this unit's finished assignments in the app's CompletedAssignment
-- shape, newest first.
create or replace function public.my_unit_history()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'incident_id', c.incident_id,
      'completed_at', c.captured_at,
      'type', coalesce(i.emergency_type, i.suggested_type),
      'barangay', i.barangay,
      'district', i.district,
      'outcome', c.outcome,
      'persons_assisted', c.persons_assisted,
      'report_delivery', 'delivered'
    ) order by c.captured_at desc), '[]'::jsonb)
  from (
    select * from public.completion_report r
     where r.unit_id = (select private.current_staff_unit())
     order by r.captured_at desc
     limit 200
  ) c
  join public.incident_report i on i.incident_id = c.incident_id
$$;

-- ------------------------------------------------------------ alerts

create or replace function public.mark_alert_read(p_alert_id text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
begin
  if uid is null then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.public_alert a where a.alert_id = p_alert_id) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  insert into public.alert_read (alert_id, user_id) values (p_alert_id, uid)
  on conflict do nothing;
end $$;

-- R7: current alerts with this account's read state, in the app's
-- PublicAlert shape.
create view public.my_alerts with (security_invoker = true) as
select
  a.alert_id, a.source, a.level, a.title, a.body, a.guidance, a.barangays,
  a.issued_at, a.is_simulated,
  exists (
    select 1 from public.alert_read r
     where r.alert_id = a.alert_id and r.user_id = (select auth.uid())
  ) as read
from public.public_alert a
where a.expires_at is null or a.expires_at > now();

grant select on public.my_alerts to authenticated;

-- ------------------------------------------------------------ privileges

revoke execute on function
  private.require_resident(), private.require_responder(), private.capture_time(timestamptz),
  private.phone_key(text), private.inside_manila(double precision, double precision),
  private.call_sign(text), private.unit_incident(text, text)
from public, anon, authenticated;

revoke execute on function
  public.link_resident(), public.register_resident(text, text, text),
  public.request_data_deletion(), public.give_consent(), public.withdraw_consent(),
  public.save_vulnerable_member(bigint, text, text[], text),
  public.remove_vulnerable_member(bigint),
  public.submit_sos(uuid, timestamptz, double precision, double precision, double precision, text, text, boolean),
  public.add_sos_details(uuid, text, int, boolean, text), public.my_sos(),
  public.submit_crowd_report(uuid, timestamptz, text, text, double precision, double precision, double precision, text, text),
  public.my_crowd_reports(),
  public.accept_assignment(text, timestamptz), public.mark_on_scene(text, timestamptz),
  public.confirm_on_scene(text, boolean, text, int, timestamptz),
  public.set_unit_status(text, timestamptz),
  public.submit_completion_report(uuid, text, timestamptz, text, int, int, int, int, int, int, text),
  public.update_unit_location(double precision, double precision, timestamptz),
  public.my_assignments(), public.my_unit_history(), public.mark_alert_read(text)
from public, anon;

grant execute on function
  public.link_resident(), public.register_resident(text, text, text),
  public.request_data_deletion(), public.give_consent(), public.withdraw_consent(),
  public.save_vulnerable_member(bigint, text, text[], text),
  public.remove_vulnerable_member(bigint),
  public.submit_sos(uuid, timestamptz, double precision, double precision, double precision, text, text, boolean),
  public.add_sos_details(uuid, text, int, boolean, text), public.my_sos(),
  public.submit_crowd_report(uuid, timestamptz, text, text, double precision, double precision, double precision, text, text),
  public.my_crowd_reports(),
  public.accept_assignment(text, timestamptz), public.mark_on_scene(text, timestamptz),
  public.confirm_on_scene(text, boolean, text, int, timestamptz),
  public.set_unit_status(text, timestamptz),
  public.submit_completion_report(uuid, text, timestamptz, text, int, int, int, int, int, int, text),
  public.update_unit_location(double precision, double precision, timestamptz),
  public.my_assignments(), public.my_unit_history(), public.mark_alert_read(text)
to authenticated;
