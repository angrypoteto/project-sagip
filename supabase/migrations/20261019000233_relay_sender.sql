-- A relayed SOS points to its real sender (Joshua, 2026-10-19).
--
-- Before: an SOS passed on over Bluetooth (Tier 3) carried no sender, so it
-- landed on the board from an unknown sender until the resident's own copy
-- arrived by internet or SMS. The phone that carried it was never shown as
-- the sender, and still is not.
--
-- Now every resident has a relay tag: 6 random bytes (12 hex digits) that
-- identify no one by themselves. The app starts each SOS id with its tag
-- (the rest of the id stays random, and it is still a version 4 UUID), so
-- the 24-byte Bluetooth packet is unchanged and the internet, SMS, and
-- Bluetooth copies keep one id (plan Q31). relay_sos() finds the resident
-- by the tag and attaches them with their consented vulnerable household,
-- as submit_sos() does. The SOS stays Pending Verification with
-- account_verified false: the sender is known only from the relay, so the
-- dashboard marks it relayed and asks the dispatcher to call and confirm.
-- When the resident's own copy arrives, account_verified becomes true.
--
-- RA 10173: the tag is broadcast only inside an SOS; it reveals no name or
-- number. Someone who copied a tag could fake an SOS in that resident's
-- name, which is why such an SOS is never treated as verified.
-- An SOS from a phone with an older app (no tag) arrives as before.

alter table public.manila_resident
  add column relay_tag text not null unique
    default substr(md5(gen_random_uuid()::text), 1, 12)
    check (relay_tag ~ '^[0-9a-f]{12}$');
comment on column public.manila_resident.relay_tag is
  'Random 12 hex digits at the start of this resident''s SOS ids, so an SOS relayed over Bluetooth names its sender. Identifies no one by itself.';

-- The signed-in resident's tag; null for anyone else.
create function public.my_relay_tag()
returns text
language sql stable security definer set search_path = ''
as $$
  select r.relay_tag from public.manila_resident r
   where r.auth_user_id = (select auth.uid())
$$;
revoke execute on function public.my_relay_tag() from public, anon;
grant execute on function public.my_relay_tag() to authenticated;

-- The resident whose tag starts [p_client_uuid], if any.
create function private.relay_sender(p_client_uuid uuid)
returns public.manila_resident
language sql stable security definer set search_path = ''
as $$
  select r.* from public.manila_resident r
   where r.relay_tag = substr(replace(p_client_uuid::text, '-', ''), 1, 12)
$$;
revoke execute on function private.relay_sender(uuid) from public, anon, authenticated;

-- The household types that raise a resident's priority, with consent only.
create function private.resident_vulnerable(p_resident public.manila_resident)
returns text[]
language sql stable security definer set search_path = ''
as $$
  select case when p_resident.consent_given_at is null then '{}'::text[]
    else coalesce((
      select array_agg(distinct t order by t)
        from public.vulnerable_member m, unnest(m.vulnerability_types) t
       where m.manila_resident_id = p_resident.manila_resident_id), '{}') end
$$;
revoke execute on function private.resident_vulnerable(public.manila_resident)
  from public, anon, authenticated;

create or replace function public.relay_sos(
  p_client_uuid uuid,
  p_captured_at timestamptz,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_mock_location boolean default false,
  p_hops int default 0
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  existing public.incident_report;
  sender public.manila_resident;
  lat double precision := p_latitude;
  lng double precision := p_longitude;
  brgy text;
  dist text;
  new_id text;
begin
  if uid is null then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  -- A suspended resident or a deactivated staff account cannot relay.
  if exists (select 1 from public.manila_resident r
              where r.auth_user_id = uid and r.suspended_at is not null)
     or exists (select 1 from public.staff s
                 where s.id = uid and s.deactivated_at is not null) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if p_client_uuid is null or (p_latitude is null) <> (p_longitude is null)
     or coalesce(p_hops, 0) not between 0 and 3 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  sender := private.relay_sender(p_client_uuid);

  select * into existing from public.incident_report i where i.client_uuid = p_client_uuid;
  if existing.incident_id is not null then
    -- Already here from another path with no sender (an SMS from an
    -- unknown number, an older relay): the tag names them now.
    if existing.manila_resident_id is null and sender.manila_resident_id is not null then
      update public.incident_report
         set manila_resident_id = sender.manila_resident_id,
             vulnerable = (select coalesce(array_agg(distinct v order by v), '{}')
                             from unnest(existing.vulnerable || private.resident_vulnerable(sender)) v)
       where incident_id = existing.incident_id;
    end if;
    insert into public.sos_relay_log (client_uuid, incident_id, relayed_by, hops, captured_at, duplicate)
    values (p_client_uuid, existing.incident_id, uid, coalesce(p_hops, 0), p_captured_at, true);
    return jsonb_build_object('incident_id', existing.incident_id, 'duplicate', true);
  end if;

  if lat is not null and not private.inside_manila(lat, lng) then
    raise exception 'outside_manila' using errcode = 'P0001';
  end if;
  if (select count(*) from public.sos_relay_log l
       where l.relayed_by = uid and l.received_at > now() - interval '1 hour') >= 30 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  if lat is not null then
    select b.name, b.district into brgy, dist from private.barangay_at(lat, lng) b;
  elsif sender.manila_resident_id is not null then
    -- No position in the packet: the sender's home barangay, as an SOS
    -- from the app without GPS.
    brgy := sender.barangay;
    dist := sender.district;
    select b.center_latitude, b.center_longitude into lat, lng
      from public.barangay b where b.name = brgy;
  end if;
  lat := coalesce(lat, 14.5995);
  lng := coalesce(lng, 120.9842);

  begin
    insert into public.incident_report (
      client_uuid, origin, channel, status, latitude, longitude, barangay, district,
      captured_at, received_at, manila_resident_id, vulnerable, account_verified, mock_location
    ) values (
      p_client_uuid, 'sos', 'bleRelay', 'pendingVerification', lat, lng,
      coalesce(brgy, 'Not known'), coalesce(dist, 'Manila'),
      private.capture_time(p_captured_at), now(), sender.manila_resident_id,
      case when sender.manila_resident_id is null then '{}'::text[]
           else private.resident_vulnerable(sender) end,
      false, coalesce(p_mock_location, false)
    ) returning incident_id into new_id;
  exception when unique_violation then
    select i.incident_id into new_id from public.incident_report i where i.client_uuid = p_client_uuid;
    insert into public.sos_relay_log (client_uuid, incident_id, relayed_by, hops, captured_at, duplicate)
    values (p_client_uuid, new_id, uid, coalesce(p_hops, 0), p_captured_at, true);
    return jsonb_build_object('incident_id', new_id, 'duplicate', true);
  end;
  insert into public.incident_event (incident_id, kind) values (new_id, 'received');
  insert into public.sos_relay_log (client_uuid, incident_id, relayed_by, hops, captured_at, duplicate)
  values (p_client_uuid, new_id, uid, coalesce(p_hops, 0), p_captured_at, false);
  return jsonb_build_object('incident_id', new_id, 'duplicate', false);
end $$;

-- submit_sos: as before, and the resident's own copy of an SOS that a relay
-- already named them on confirms them (account_verified).
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

  -- Vulnerable household types raise priority (FR2), only with consent.
  vuln := private.resident_vulnerable(me);

  select * into existing from public.incident_report i where i.client_uuid = p_client_uuid;
  if existing.incident_id is not null then
    if existing.manila_resident_id is null and existing.channel in ('sms', 'bleRelay') then
      update public.incident_report
         set manila_resident_id = me.manila_resident_id, account_verified = true,
             vulnerable = (select coalesce(array_agg(distinct v order by v), '{}')
                             from unnest(existing.vulnerable || vuln) v)
       where incident_id = existing.incident_id;
      return existing.incident_id;
    end if;
    if existing.manila_resident_id is distinct from me.manila_resident_id then
      raise exception 'not_allowed' using errcode = 'P0001';
    end if;
    -- Named by a relay; now confirmed by the resident's own phone.
    if not existing.account_verified then
      update public.incident_report
         set account_verified = true,
             vulnerable = (select coalesce(array_agg(distinct v order by v), '{}')
                             from unnest(existing.vulnerable || vuln) v)
       where incident_id = existing.incident_id;
    end if;
    return existing.incident_id;
  end if;

  if lat is null then
    select b.center_latitude, b.center_longitude into lat, lng
      from public.barangay b where b.name = brgy;
    lat := coalesce(lat, 14.5995);
    lng := coalesce(lng, 120.9842);
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
