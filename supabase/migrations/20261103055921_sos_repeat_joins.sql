-- Surge test finding 2 (NFR7, docs/SURGE-TEST.md; Joshua, 2026-11-03: "fix
-- it"): one account could send any number of SOS (200 in a row were all
-- stored), but NFR7 promises per-account limiting against single-source
-- flooding. An SOS must never be refused, so a repeat joins instead:
--
-- A new SOS from an account that already has an open SOS (not resolved, not
-- cancelled) last received within the past 10 minutes becomes part of that
-- one. Its latest location is updated (the same columns live location
-- uses), a "received" event notes "SOS sent again from the app" (a kind
-- every app and dashboard build already knows), and its incident number is
-- returned, so the phone shows the same SOS. After 10 minutes without a new
-- press, a new SOS is a new incident again: at most 6 incidents an hour from
-- one account. Everything else in submit_sos is unchanged.

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
language plpgsql
security definer
set search_path = ''
as $$
declare
  me public.manila_resident := private.require_resident();
  existing public.incident_report;
  open_sos public.incident_report;
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

  -- A repeat within 10 minutes of the last press joins the open SOS
  -- (NFR7, 2026-11-03).
  select i.* into open_sos
    from public.incident_report i
   where i.manila_resident_id = me.manila_resident_id
     and i.origin = 'sos'
     and i.status <> 'resolved'
     and not coalesce(i.cancelled, false)
     and (select max(e.at) from public.incident_event e
           where e.incident_id = i.incident_id and e.kind = 'received') > now() - interval '10 minutes'
   order by i.received_at desc
   limit 1
   for update;
  if open_sos.incident_id is not null then
    if p_latitude is not null then
      update public.incident_report
         set last_latitude = p_latitude, last_longitude = p_longitude,
             last_accuracy_m = p_accuracy_m, last_location_at = private.capture_time(p_captured_at)
       where incident_id = open_sos.incident_id
         and (last_location_at is null or last_location_at <= private.capture_time(p_captured_at));
    end if;
    insert into public.incident_event (incident_id, kind, detail)
    values (open_sos.incident_id, 'received', 'SOS sent again from the app');
    return open_sos.incident_id;
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
