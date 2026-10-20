-- An SOS texted to the gateway (Tier 2) names the barangay where the text
-- says the phone is, like an SOS from the app (submit_sos takes the
-- barangay the app found for its location). It used the resident's home
-- barangay whenever the sender was registered, so a resident texting from
-- elsewhere showed the right pin under the wrong barangay (2026-10-20).
-- The home barangay is still used, at its centre, when the text has no
-- location. Nothing else changes.

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

  if lat is not null then
    -- Where the text says the phone is.
    select b.name, b.district into brgy, dist from private.barangay_at(lat, lng) b;
  else
    -- No location in the text: the resident's home barangay, at its centre.
    brgy := r.barangay;
    dist := r.district;
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
