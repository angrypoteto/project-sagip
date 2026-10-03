-- Tier 3: SOS passed on over Bluetooth LE (plan section 11, Q31, Q32;
-- proof of concept). A phone with neither internet nor cellular signal
-- advertises its SOS in a 24-byte packet (packages/shared sos_relay.dart);
-- phones nearby running the app keep it, pass it on up to three hops, and
-- upload it with relay_sos() as soon as one of them is online.
--
-- - The packet has the SOS's client UUID, capture time, location, and the
--   mock-location flag; no name or number (RA 10173). The SOS lands on the
--   board at once as Pending Verification from an unknown sender (FR8), as
--   an SMS from an unknown number does.
-- - The same SOS from several relays, by SMS, or from the app later is one
--   incident (client UUID, Q31); the app's own copy attaches the resident.
-- - Every upload is logged in sos_relay_log (who uploaded it, how many hops,
--   and whether the server already had it), readable by no app: it is for
--   abuse checks and the Objective 3 trials. An account may upload 30
--   relayed packets an hour, so a relay cannot flood the board.

create table public.sos_relay_log (
  relay_id bigint generated always as identity primary key,
  client_uuid uuid not null,
  incident_id text references public.incident_report (incident_id) on delete set null,
  relayed_by uuid not null references auth.users (id) on delete cascade,
  hops smallint not null check (hops between 0 and 3),
  captured_at timestamptz,
  duplicate boolean not null,
  received_at timestamptz not null default now()
);
comment on table public.sos_relay_log is
  'Tier 3: every relayed SOS packet uploaded, by whom and how many hops. Service role only.';
create index sos_relay_log_by_idx on public.sos_relay_log (relayed_by, received_at desc);
create index sos_relay_log_sos_idx on public.sos_relay_log (client_uuid);
alter table public.sos_relay_log enable row level security;
-- No policies and no grants: only the service role reads it.

-- Any signed-in account (a resident's or a responder's phone) can upload an
-- SOS it heard. Returns {incident_id, duplicate}.
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

  select * into existing from public.incident_report i where i.client_uuid = p_client_uuid;
  if existing.incident_id is not null then
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
  else
    lat := 14.5995;
    lng := 120.9842;
  end if;

  begin
    insert into public.incident_report (
      client_uuid, origin, channel, status, latitude, longitude, barangay, district,
      captured_at, received_at, account_verified, mock_location
    ) values (
      p_client_uuid, 'sos', 'bleRelay', 'pendingVerification', lat, lng,
      coalesce(brgy, 'Not known'), coalesce(dist, 'Manila'),
      private.capture_time(p_captured_at), now(), false,
      coalesce(p_mock_location, false)
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

revoke all on function public.relay_sos(uuid, timestamptz, double precision, double precision, boolean, int)
  from public, anon;
grant execute on function public.relay_sos(uuid, timestamptz, double precision, double precision, boolean, int)
  to authenticated;

-- submit_sos: the app's own copy of an SOS that first arrived by SMS from an
-- unknown number OR by a Bluetooth relay attaches the signed-in resident
-- (otherwise as in the sms_intake migration).
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
