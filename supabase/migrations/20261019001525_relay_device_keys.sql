-- A relayed SOS names its sender through a key only that phone holds
-- (Joshua, 2026-10-19), in place of the relay tag of the migration
-- relay_sender (the same day), which could be copied and followed.
--
-- Each phone makes a random 32-byte secret at sign-in, keeps it in
-- Android's protected storage, and sends it once to the server
-- (register_relay_key). The SOS id the phone makes is then a code of that
-- secret and the SOS's own time, place, and mock flag (HMAC-SHA256, shaped
-- as a version 4 UUID). The 24-byte Bluetooth packet is unchanged and the
-- internet, SMS, and Bluetooth copies keep one id (plan Q31).
--
-- - Phones that pass the SOS on, and anyone scanning Bluetooth, see an id
--   that is different for every SOS and names no one: only the server can
--   work back from it to the sender.
-- - It cannot be faked without the phone's secret; a copied packet only
--   repeats the same SOS, which is one incident. A packet whose place or
--   time was changed no longer matches, and arrives from an unknown sender.
-- - When the code matches a phone's key, relay_sos() attaches that
--   resident with their consented household and marks the account
--   verified (the phone proved itself, as an app sign-in does). The SOS
--   itself stays Pending Verification: the dispatcher still checks it.
-- - A phone with an older app (random ids) arrives from an unknown sender.
--
-- The code (the app's `relaySosId` in packages/shared sos_relay.dart makes
-- the same one): message `sagip-relay-v1|<capture time, Unix seconds>|
-- <dlat>,<dlng>|<mock 1 or 0>`, where dlat and dlng are the packet's
-- 0.00001-degree offsets from 14.4 N and 120.9 E (or `-` with no place, or
-- one outside the packet's box); the first 16 bytes of HMAC-SHA256(secret,
-- message), with the UUID version (4) and variant bits set.

create table public.relay_device (
  device_id uuid primary key default gen_random_uuid(),
  -- The order phones were handed over in (created_at is the same within
  -- one transaction).
  seq bigint generated always as identity,
  manila_resident_id text not null
    references public.manila_resident (manila_resident_id) on delete cascade,
  secret bytea not null check (octet_length(secret) = 32),
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);
comment on table public.relay_device is
  'Each resident phone''s relay secret: an SOS relayed over Bluetooth names its sender through it. No app reads it.';
create index relay_device_active_idx on public.relay_device (manila_resident_id)
  where revoked_at is null;
alter table public.relay_device enable row level security;
-- No policies and no grants: only the functions below use it.
revoke all on public.relay_device from public, anon, authenticated;

-- The SOS id a phone with [p_secret] makes for an SOS.
create function private.relay_code(
  p_secret bytea,
  p_captured_at timestamptz,
  p_latitude double precision,
  p_longitude double precision,
  p_mock boolean
)
returns uuid
language plpgsql immutable set search_path = ''
as $$
declare
  d_lat bigint;
  d_lng bigint;
  loc text := '-';
  h bytea;
begin
  if p_latitude is not null and p_longitude is not null then
    d_lat := floor((p_latitude - 14.4) * 1e5 + 0.5);
    d_lng := floor((p_longitude - 120.9) * 1e5 + 0.5);
    if d_lat between 0 and 65535 and d_lng between 0 and 65535 then
      loc := d_lat || ',' || d_lng;
    end if;
  end if;
  h := substring(extensions.hmac(
         convert_to('sagip-relay-v1|' || floor(extract(epoch from p_captured_at))::bigint
                    || '|' || loc || '|' || case when coalesce(p_mock, false) then '1' else '0' end,
                    'UTF8'),
         p_secret, 'sha256') from 1 for 16);
  h := set_byte(h, 6, (get_byte(h, 6) & 15) | 64);
  h := set_byte(h, 8, (get_byte(h, 8) & 63) | 128);
  return encode(h, 'hex')::uuid;
end $$;

-- The phone (and so the resident) whose secret made [p_client_uuid].
create function private.relay_device_for(
  p_client_uuid uuid,
  p_captured_at timestamptz,
  p_latitude double precision,
  p_longitude double precision,
  p_mock boolean
)
returns public.relay_device
language sql stable security definer set search_path = ''
as $$
  select d.* from public.relay_device d
   where d.revoked_at is null
     and private.relay_code(d.secret, p_captured_at, p_latitude, p_longitude, p_mock) = p_client_uuid
   limit 1
$$;

revoke execute on function
  private.relay_code(bytea, timestamptz, double precision, double precision, boolean),
  private.relay_device_for(uuid, timestamptz, double precision, double precision, boolean)
  from public, anon, authenticated;

-- A resident's phone hands over its secret (64 hex digits) once, signed in
-- and online. A resident keeps at most five phones; an older one is
-- retired. Returns the phone's id.
create function public.register_relay_key(p_key text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  me public.manila_resident := private.require_resident();
  new_id uuid;
begin
  if p_key is null or p_key !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select d.device_id into new_id from public.relay_device d
   where d.manila_resident_id = me.manila_resident_id and d.revoked_at is null
     and d.secret = decode(p_key, 'hex');
  if new_id is not null then
    return new_id;
  end if;
  insert into public.relay_device (manila_resident_id, secret)
  values (me.manila_resident_id, decode(p_key, 'hex'))
  returning device_id into new_id;
  update public.relay_device set revoked_at = now()
   where manila_resident_id = me.manila_resident_id and revoked_at is null
     and device_id not in (
       select d.device_id from public.relay_device d
        where d.manila_resident_id = me.manila_resident_id and d.revoked_at is null
        order by d.seq desc limit 5);
  return new_id;
end $$;
revoke execute on function public.register_relay_key(text) from public, anon;
grant execute on function public.register_relay_key(text) to authenticated;

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
  device public.relay_device;
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
  device := private.relay_device_for(p_client_uuid, p_captured_at, p_latitude, p_longitude,
                                     coalesce(p_mock_location, false));
  if device.device_id is not null then
    select * into sender from public.manila_resident r
     where r.manila_resident_id = device.manila_resident_id;
    update public.relay_device set last_used_at = now() where device_id = device.device_id;
  end if;

  select * into existing from public.incident_report i where i.client_uuid = p_client_uuid;
  if existing.incident_id is not null then
    -- Already here from another path with no sender (an SMS from an
    -- unknown number): the phone's code names them now.
    if existing.manila_resident_id is null and sender.manila_resident_id is not null then
      update public.incident_report
         set manila_resident_id = sender.manila_resident_id, account_verified = true,
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
      sender.manila_resident_id is not null, coalesce(p_mock_location, false)
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

-- The relay tag of the migration relay_sender is no longer used: nobody
-- may call its functions. (Dropping them is left to Joshua in the SQL
-- editor: `drop function public.my_relay_tag(); drop function
-- private.relay_sender(uuid); alter table public.manila_resident drop
-- column relay_tag;`, as with private.unit_returns_home().)
revoke execute on function public.my_relay_tag() from public, anon, authenticated;
comment on column public.manila_resident.relay_tag is
  'Not used (replaced by relay_device on 2026-10-19); to be dropped.';

-- ------------------------------------------------ forced app update

-- The oldest app build allowed to run (A3). An older app shows "Update
-- S.A.G.I.P." with the download link and keeps only SOS and the hotline
-- (Joshua, 2026-10-19: "force them to be updated unless there is really an
-- emergency"). Offline the app cannot know and never blocks. Apps before
-- build 2 have no such check.
alter table public.app_setting drop constraint app_setting_category_check;
alter table public.app_setting add constraint app_setting_category_check check (category in (
  'priority', 'reports', 'alerts', 'channels', 'contact', 'demo', 'privacy', 'inventory', 'app'
));
insert into public.app_setting (key, category, value, min_value, max_value, description) values
  ('app.min_build', 'app', '1', 1, 100000,
   'The oldest mobile app build allowed; older apps must update (SOS still works)');

create or replace function public.client_config()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'hotline', private.setting_text('contact.hotline'),
    'sms_gateway', private.setting_text('contact.sms_gateway'),
    'min_build', coalesce(private.setting_number('app.min_build'), 1))
$$;
