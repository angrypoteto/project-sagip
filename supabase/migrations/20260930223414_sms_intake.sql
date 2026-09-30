-- Tier 2 SOS by SMS (plan section 11, NFR1, FR8).
--
-- When a phone has signal but no data, the app texts the SOS to the MDRRMD
-- gateway SIM in the SAGIP1 format (packages/shared sos_sms.dart). The
-- gateway forwards it to the sms-intake Edge Function, which checks the
-- checksum and calls intake_sms_sos() with the service-role key. The SOS
-- lands on the board at once, like one sent over the internet.
--
-- - The sender's number finds the resident (the same match as sign-in);
--   an unknown number still creates the SOS, marked not account-verified.
-- - The SOS keeps the phone's id, so the copy the app sends later over the
--   internet is recognised, not doubled. If the SMS came from an unknown
--   number (another SIM), the app's copy attaches the resident.
-- - Inbound messages are kept in sms_log (no client access).

alter table public.sms_log drop constraint sms_log_kind_check;
alter table public.sms_log add constraint sms_log_kind_check
  check (kind in ('otp', 'alert', 'ack', 'inbound'));
alter table public.sms_log drop constraint sms_log_status_check;
alter table public.sms_log add constraint sms_log_status_check
  check (status in ('sent', 'failed', 'notSent', 'received', 'unreadable'));

-- The barangay a point falls in: its boundary once loaded, else the nearest
-- sample centre.
create or replace function private.barangay_at(p_lat double precision, p_lng double precision)
returns table (name text, district text)
language sql stable security definer set search_path = ''
as $$
  select b.name, b.district
    from public.barangay b
   order by
     case when b.boundary is not null and extensions.st_covers(
       b.boundary, extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography)
     then 0 else 1 end,
     (b.center_latitude - p_lat) ^ 2 + ((b.center_longitude - p_lng) * cos(radians(p_lat))) ^ 2
   limit 1
$$;

create or replace function public.intake_sms_sos(
  p_from text,
  p_client_uuid uuid,
  p_captured_at timestamptz,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_accuracy_m double precision default null,
  p_mock_location boolean default false
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  r public.manila_resident;
  existing public.incident_report;
  lat double precision := p_latitude;
  lng double precision := p_longitude;
  brgy text;
  dist text;
  vuln text[] := '{}';
  new_id text;
begin
  if p_client_uuid is null or (p_latitude is null) <> (p_longitude is null)
     or length(private.phone_key(p_from)) < 10 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if p_latitude is not null
     and (p_latitude not between -90 and 90 or p_longitude not between -180 and 180) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  select * into r from public.manila_resident m
   where private.phone_key(m.contact_number) = private.phone_key(p_from)
   order by m.auth_user_id is null, m.manila_resident_id
   limit 1;

  select * into existing from public.incident_report i where i.client_uuid = p_client_uuid;
  if existing.incident_id is not null then
    return jsonb_build_object(
      'incident_id', existing.incident_id, 'duplicate', true,
      'known', r.manila_resident_id is not null, 'first_channel', existing.channel);
  end if;

  brgy := r.barangay;
  dist := r.district;
  if lat is not null and brgy is null then
    select b.name, b.district into brgy, dist from private.barangay_at(lat, lng) b;
  end if;
  if lat is null then
    select b.center_latitude, b.center_longitude into lat, lng
      from public.barangay b where b.name = brgy;
    lat := coalesce(lat, 14.5995);
    lng := coalesce(lng, 120.9842);
  end if;
  brgy := coalesce(brgy, 'Not known');
  dist := coalesce(dist, 'Manila');

  if r.consent_given_at is not null then
    select coalesce(array_agg(distinct t order by t), '{}') into vuln
      from public.vulnerable_member m, unnest(m.vulnerability_types) t
     where m.manila_resident_id = r.manila_resident_id;
  end if;

  begin
    insert into public.incident_report (
      client_uuid, origin, channel, status, latitude, longitude, barangay, district,
      accuracy_m, captured_at, received_at, manila_resident_id, vulnerable,
      account_verified, mock_location
    ) values (
      p_client_uuid, 'sos', 'sms', 'pendingVerification', lat, lng, brgy, dist,
      case when p_latitude is null then null else p_accuracy_m end,
      private.capture_time(p_captured_at), now(), r.manila_resident_id, vuln,
      r.manila_resident_id is not null, coalesce(p_mock_location, false)
    ) returning incident_id into new_id;
  exception when unique_violation then
    select i.incident_id into new_id from public.incident_report i where i.client_uuid = p_client_uuid;
    return jsonb_build_object('incident_id', new_id, 'duplicate', true,
      'known', r.manila_resident_id is not null, 'first_channel', 'app');
  end;
  insert into public.incident_event (incident_id, kind) values (new_id, 'received');
  return jsonb_build_object('incident_id', new_id, 'duplicate', false,
    'known', r.manila_resident_id is not null, 'first_channel', 'sms');
end $$;

-- submit_sos: the app's copy of an SOS that arrived first by SMS from an
-- unknown number attaches the signed-in resident (otherwise as in the
-- mobile_actions migration).
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
  if me.consent_given_at is not null then
    select coalesce(array_agg(distinct t order by t), '{}') into vuln
      from public.vulnerable_member m, unnest(m.vulnerability_types) t
     where m.manila_resident_id = me.manila_resident_id;
  end if;

  select * into existing from public.incident_report i where i.client_uuid = p_client_uuid;
  if existing.incident_id is not null then
    if existing.manila_resident_id is null and existing.channel = 'sms' then
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

-- The gateway path runs with the service-role key only.
revoke execute on function
  public.intake_sms_sos(text, uuid, timestamptz, double precision, double precision, double precision, boolean)
from public, anon, authenticated;
grant execute on function
  public.intake_sms_sos(text, uuid, timestamptz, double precision, double precision, double precision, boolean)
to service_role;
revoke execute on function private.barangay_at(double precision, double precision)
from public, anon, authenticated;
