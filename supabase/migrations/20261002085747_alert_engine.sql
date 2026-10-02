-- The rest of A3 Configuration and the threshold engine (plan 7.4 A3 and
-- section 12; FR5, FR6).
--
-- New settings: alert thresholds for PAGASA readings, channel switches
-- (push, SMS, Facebook), the MDRRMD hotline and the SMS gateway number the
-- apps show, and simulation mode. (The data retention period waits for a
-- decision on what is removed and when.)
--
-- The threshold engine: when a new weather reading crosses a threshold, the
-- database issues an alert for residents by itself and logs one delivery
-- row per channel. The in-app alert is immediate. Push, SMS, and Facebook
-- rows wait as "queued" for the sender (an Edge Function, not built into
-- this migration); a switched-off channel is logged as "off". Simulated
-- readings (simulation mode) raise simulated alerts, which are shown in the
-- apps but never texted or posted.
--
-- Everything here is added; nothing existing is changed except set_setting
-- (same behaviour for the settings that already exist).

-- ------------------------------------------------------------ settings

alter table public.app_setting drop constraint app_setting_category_check;
alter table public.app_setting add constraint app_setting_category_check
  check (category in ('priority', 'reports', 'alerts', 'channels', 'contact', 'demo'));

-- Provisional thresholds until MDRRMD confirms them. Rainfall follows
-- PAGASA's heavy rainfall warnings (orange from 15 mm/hr, red from 30);
-- storm surge follows PAGASA's risk bands (moderate above 1 m, high above
-- 2 m).
insert into public.app_setting (key, category, value, min_value, max_value, description) values
  ('alerts.rainfall_warning', 'alerts', '15', 1, 200, 'Rainfall in mm per hour that raises a warning alert'),
  ('alerts.rainfall_critical', 'alerts', '30', 1, 200, 'Rainfall in mm per hour that raises a critical alert'),
  ('alerts.signal_warning', 'alerts', '1', 1, 5, 'Wind signal that raises a warning alert'),
  ('alerts.signal_critical', 'alerts', '3', 1, 5, 'Wind signal that raises a critical alert'),
  ('alerts.surge_warning', 'alerts', '1.1', 0.1, 10, 'Storm surge height in metres that raises a warning alert'),
  ('alerts.surge_critical', 'alerts', '2.1', 0.1, 10, 'Storm surge height in metres that raises a critical alert'),
  ('channels.push', 'channels', 'true', null, null, 'Send alerts as push notifications'),
  ('channels.sms', 'channels', 'true', null, null, 'Send alerts by SMS (Semaphore)'),
  ('channels.facebook', 'channels', 'false', null, null, 'Post alerts on the MDRRMD Facebook Page'),
  ('contact.hotline', 'contact', '""', null, null, 'The MDRRMD hotline the apps show'),
  ('contact.sms_gateway', 'contact', '""', null, null, 'The gateway SIM that receives an SOS by SMS'),
  ('demo.simulation', 'demo', 'false', null, null, 'Simulation mode for demos and UAT');

create or replace function private.setting_flag(p_key text)
returns boolean
language sql stable security definer set search_path = ''
as $$ select coalesce((s.value #>> '{}')::boolean, false) from public.app_setting s where s.key = p_key $$;

create or replace function private.setting_text(p_key text)
returns text
language sql stable security definer set search_path = ''
as $$ select coalesce(s.value #>> '{}', '') from public.app_setting s where s.key = p_key $$;

-- Setting changes: numbers stay in their range, each warning stays at or
-- below its critical value, switches stay switches, and the two numbers
-- are checked (the gateway must be a Philippine mobile number and is kept
-- as +639XXXXXXXXX). Admins only; every change is audited (FR11).
create or replace function public.set_setting(p_key text, p_value jsonb)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  s public.app_setting;
  v numeric;
  t text;
  new_value jsonb := p_value;
  pair record;
begin
  select * into s from public.app_setting a where a.key = p_key for update;
  if s.key is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if p_value is null or jsonb_typeof(p_value) <> jsonb_typeof(s.value) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  if jsonb_typeof(p_value) = 'number' then
    v := (p_value #>> '{}')::numeric;
    if (s.min_value is not null and v < s.min_value) or (s.max_value is not null and v > s.max_value) then
      raise exception 'invalid_value' using errcode = 'P0001';
    end if;
    for pair in
      select * from (values
        ('priority.high_at', 'priority.critical_at'),
        ('alerts.rainfall_warning', 'alerts.rainfall_critical'),
        ('alerts.signal_warning', 'alerts.signal_critical'),
        ('alerts.surge_warning', 'alerts.surge_critical')
      ) as x(low, high)
    loop
      if (p_key = pair.low and v > private.setting_number(pair.high))
         or (p_key = pair.high and v < private.setting_number(pair.low)) then
        raise exception 'invalid_value' using errcode = 'P0001';
      end if;
    end loop;
  elsif jsonb_typeof(p_value) = 'string' then
    t := btrim(p_value #>> '{}');
    if p_key = 'contact.sms_gateway' then
      if t <> '' then
        t := private.phone_key(t);
        if t !~ '^9[0-9]{9}$' then
          raise exception 'invalid_value' using errcode = 'P0001';
        end if;
        t := '+63' || t;
      end if;
    elsif p_key = 'contact.hotline' then
      if length(t) > 40 or (t <> '' and t !~ '^[0-9+() -]*[0-9][0-9+() -]*$') then
        raise exception 'invalid_value' using errcode = 'P0001';
      end if;
    elsif length(t) > 200 then
      raise exception 'invalid_value' using errcode = 'P0001';
    end if;
    new_value := to_jsonb(t);
  end if;

  if s.value = new_value then
    return;
  end if;
  update public.app_setting
     set value = new_value, updated_at = now(), updated_by = me.display_name
   where key = p_key;
  insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id, detail)
  values (me.id::text, me.display_name, me.role, 'settingChanged', 'app_setting', p_key,
          (s.value #>> '{}') || ' → ' || (new_value #>> '{}'));
end $$;

-- What the apps may show before anyone signs in: the hotline and the
-- gateway number. Both are public numbers; nothing else is exposed.
create or replace function public.client_config()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'hotline', private.setting_text('contact.hotline'),
    'sms_gateway', private.setting_text('contact.sms_gateway'))
$$;

-- ------------------------------------------------------------ readings and alerts

alter table public.weather_alert
  add column storm_surge_m numeric(4, 1) check (storm_surge_m >= 0);
comment on column public.weather_alert.storm_surge_m is
  'Forecast storm surge height in metres; null when there is no advisory.';

alter table public.public_alert
  add column hazard text check (hazard in ('rainfall', 'signal', 'surge')),
  add column weather_alert_id bigint references public.weather_alert (alert_id) on delete set null;
comment on column public.public_alert.hazard is
  'Set on alerts the threshold engine issued: which reading crossed its threshold.';

create or replace function private.alert_level(p_value numeric, p_warning numeric, p_critical numeric)
returns text
language sql immutable set search_path = ''
as $$
  select case
    when p_value is null then null
    when p_value >= p_critical then 'critical'
    when p_value >= p_warning then 'warning'
  end
$$;

create or replace function private.level_rank(p_level text)
returns int
language sql immutable set search_path = ''
as $$ select case p_level when 'critical' then 2 when 'warning' then 1 else 0 end $$;

-- 18.0 as "18", 2.5 as "2.5".
create or replace function private.plain_number(p numeric)
returns text
language sql immutable set search_path = ''
as $$ select case when p = trunc(p) then trunc(p)::text else p::text end $$;

-- The words of an automatic alert. Plain text written here, not PAGASA's
-- bulletin: the reading is PAGASA's, the alert is S.A.G.I.P.'s.
create or replace function private.weather_alert_text(p_hazard text, p_level text, p_value numeric)
returns table (title text, body text, guidance text[])
language sql immutable set search_path = ''
as $$
  select x.title, x.body, x.guidance
  from (values
    ('rainfall', 'warning',
     'Heavy rainfall warning',
     'PAGASA reports rain of ' || private.plain_number(p_value) || ' mm per hour over Manila. Flooding is possible in low-lying areas.',
     array['Move appliances and important papers to a higher place.',
           'Avoid wading in floodwater; it can carry disease and live wires.',
           'Prepare a go-bag with water, food, medicine, and a flashlight.']),
    ('rainfall', 'critical',
     'Torrential rainfall warning',
     'PAGASA reports rain of ' || private.plain_number(p_value) || ' mm per hour over Manila. Serious flooding is expected in low-lying areas.',
     array['Move to higher ground if water is rising where you are.',
           'Do not walk or drive through floodwater.',
           'If you need rescue, hold the SOS button in the app.']),
    ('signal', 'warning',
     'Wind Signal No. ' || private.plain_number(p_value) || ' raised over Manila',
     'PAGASA raised Tropical Cyclone Wind Signal No. ' || private.plain_number(p_value) || '. Strong winds are expected.',
     array['Secure or bring in loose objects outside your home.',
           'Stay indoors unless MDRRMD tells you to leave.',
           'Charge your phone and prepare a go-bag.']),
    ('signal', 'critical',
     'Wind Signal No. ' || private.plain_number(p_value) || ' raised over Manila',
     'PAGASA raised Tropical Cyclone Wind Signal No. ' || private.plain_number(p_value) || '. Destructive winds are expected.',
     array['Stay indoors and away from windows.',
           'Follow evacuation instructions from MDRRMD and your barangay.',
           'If you need rescue, hold the SOS button in the app.']),
    ('surge', 'warning',
     'Storm surge warning for Manila Bay',
     'A storm surge of up to ' || private.plain_number(p_value) || ' m is possible along Manila Bay.',
     array['Stay away from the coast and seawalls.',
           'Move vehicles and belongings to higher ground.']),
    ('surge', 'critical',
     'Storm surge warning for Manila Bay',
     'A storm surge of up to ' || private.plain_number(p_value) || ' m is expected along Manila Bay. Coastal areas may flood quickly.',
     array['Leave coastal and low-lying areas now if told to evacuate.',
           'Stay away from the coast and seawalls.',
           'If you need rescue, hold the SOS button in the app.'])
  ) as x(hazard, level, title, body, guidance)
  where x.hazard = p_hazard and x.level = p_level
$$;

-- The threshold engine (FR5). Compares each new reading with the one
-- before it, per hazard. When the level changes, earlier automatic alerts
-- for that hazard expire; when the new level is a warning or critical, a
-- new alert is issued. A reading that is not the newest (a late arrival)
-- changes nothing, and the very first reading only sets the baseline (so
-- loading the demo data, which starts with one reading and its own sample
-- alerts, raises nothing).
create or replace function private.raise_weather_alerts()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  prev public.weather_alert;
  scope text[] := case when new.barangay is null then '{}'::text[] else array[new.barangay] end;
  h record;
  now_level text;
  prev_level text;
begin
  if exists (select 1 from public.weather_alert w
              where w.barangay is not distinct from new.barangay
                and (w.issued_at, w.alert_id) > (new.issued_at, new.alert_id)) then
    return new;
  end if;
  select * into prev from public.weather_alert w
   where w.barangay is not distinct from new.barangay
     and (w.issued_at, w.alert_id) < (new.issued_at, new.alert_id)
   order by w.issued_at desc, w.alert_id desc
   limit 1;
  if prev.alert_id is null then
    return new;
  end if;

  for h in
    select * from (values
      ('rainfall', new.rainfall_intensity::numeric, prev.rainfall_intensity::numeric,
       'alerts.rainfall_warning', 'alerts.rainfall_critical'),
      ('signal', new.signal_level::numeric, prev.signal_level::numeric,
       'alerts.signal_warning', 'alerts.signal_critical'),
      ('surge', new.storm_surge_m::numeric, prev.storm_surge_m::numeric,
       'alerts.surge_warning', 'alerts.surge_critical')
    ) as x(hazard, value, before, warning_key, critical_key)
  loop
    now_level := private.alert_level(h.value,
      private.setting_number(h.warning_key), private.setting_number(h.critical_key));
    prev_level := private.alert_level(h.before,
      private.setting_number(h.warning_key), private.setting_number(h.critical_key));
    continue when private.level_rank(now_level) = private.level_rank(prev_level);

    update public.public_alert a set expires_at = now()
     where a.hazard = h.hazard and a.barangays = scope
       and (a.expires_at is null or a.expires_at > now());
    if now_level is not null then
      insert into public.public_alert
        (source, level, title, body, guidance, barangays, issued_at, is_simulated, hazard, weather_alert_id)
      select 'pagasa', now_level, t.title, t.body, t.guidance, scope, new.issued_at,
             new.is_simulated, h.hazard, new.alert_id
        from private.weather_alert_text(h.hazard, now_level, h.value) t;
    end if;
  end loop;
  return new;
end $$;

create trigger weather_alert_thresholds
  after insert on public.weather_alert
  for each row execute function private.raise_weather_alerts();

-- ------------------------------------------------------------ delivery log

-- One row per alert and channel (plan D10: "log of alerts sent").
create table public.alert_delivery (
  delivery_id bigint generated always as identity primary key,
  alert_id text not null references public.public_alert (alert_id) on delete cascade,
  channel text not null check (channel in ('app', 'push', 'sms', 'facebook')),
  -- queued: waiting for the sender. off: the channel was switched off on
  -- A3. simulated: a simulated alert, never sent outside the apps.
  -- notSetUp: the channel has no provider yet.
  status text not null check (status in ('queued', 'sent', 'failed', 'off', 'simulated', 'notSetUp')),
  recipients int check (recipients >= 0),
  delivered int check (delivered >= 0),
  failed int check (failed >= 0),
  detail text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (alert_id, channel)
);
comment on table public.alert_delivery is
  'What happened to each alert on each channel (FR6). Counts only, no numbers.';
create index alert_delivery_status_idx on public.alert_delivery (status) where status = 'queued';

alter table public.alert_delivery enable row level security;
create policy "alert deliveries: dispatchers and admins" on public.alert_delivery
  for select to authenticated using ((select private.is_dispatcher()));
grant select on public.alert_delivery to authenticated;
alter publication supabase_realtime add table public.alert_delivery;

create or replace function private.queue_alert_deliveries()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.alert_delivery (alert_id, channel, status)
  select new.alert_id, c.channel,
         case
           when c.channel = 'app' then 'sent'
           when new.is_simulated then 'simulated'
           when not private.setting_flag('channels.' || c.channel) then 'off'
           else 'queued'
         end
    from (values ('app'), ('push'), ('sms'), ('facebook')) as c(channel);
  return new;
end $$;

create trigger public_alert_deliveries
  after insert on public.public_alert
  for each row execute function private.queue_alert_deliveries();

-- Alerts already on the project get their in-app row.
insert into public.alert_delivery (alert_id, channel, status)
select a.alert_id, c.channel, case when c.channel = 'app' then 'sent' else 'simulated' end
  from public.public_alert a
 cross join (values ('app'), ('push'), ('sms'), ('facebook')) as c(channel)
 where a.is_simulated;

-- ------------------------------------------------------------ simulation mode

alter table public.audit_log drop constraint audit_log_action_type_check;
alter table public.audit_log add constraint audit_log_action_type_check check (action_type in (
  'verified', 'markedFalseReport', 'typeConfirmed', 'unitAssigned', 'unitReassigned',
  'statusChanged', 'resolved', 'smsCheckSent', 'contactViewed', 'settingChanged',
  'unitAdded', 'unitEdited', 'unitRetired', 'unitRestored', 'rosterChanged',
  'accountCreated', 'accountUpdated', 'accountDeactivated', 'accountReactivated',
  'passwordReset', 'residentSuspended', 'residentRestored', 'weatherSimulated'
));

-- A simulated PAGASA reading for demos and UAT (plan section 12). Admins
-- only, only while simulation mode is on, and audited. The threshold
-- engine treats it like any reading; the alerts it raises are marked
-- simulated.
create or replace function public.simulate_weather(
  p_signal int,
  p_rainfall numeric,
  p_surge_m numeric default null
)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  new_id bigint;
begin
  if not private.setting_flag('demo.simulation') then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if p_signal is null or p_signal not between 0 and 5
     or p_rainfall is null or p_rainfall not between 0 and 500
     or (p_surge_m is not null and p_surge_m not between 0 and 10) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  insert into public.weather_alert
    (signal_level, rainfall_intensity, storm_surge_advisory, storm_surge_m, is_simulated)
  values (
    p_signal, p_rainfall,
    case when coalesce(p_surge_m, 0) > 0
         then 'Storm surge up to ' || private.plain_number(p_surge_m) || ' m possible along Manila Bay' end,
    nullif(p_surge_m, 0), true)
  returning alert_id into new_id;
  perform private.audit_admin(me, 'weatherSimulated', 'weather_alert', new_id::text,
    'Signal ' || p_signal || ', ' || private.plain_number(p_rainfall) || ' mm/hr'
      || case when coalesce(p_surge_m, 0) > 0
              then ', surge ' || private.plain_number(p_surge_m) || ' m' else '' end);
  return new_id;
end $$;

-- ------------------------------------------------------------ privileges

revoke execute on function
  private.setting_flag(text), private.setting_text(text),
  private.alert_level(numeric, numeric, numeric), private.level_rank(text),
  private.plain_number(numeric), private.weather_alert_text(text, text, numeric),
  private.raise_weather_alerts(), private.queue_alert_deliveries()
from public, anon, authenticated;

revoke execute on function public.simulate_weather(int, numeric, numeric) from public, anon;
grant execute on function public.simulate_weather(int, numeric, numeric) to authenticated;

-- The hotline is shown on the sign-in screens, before there is an account.
revoke execute on function public.client_config() from public;
grant execute on function public.client_config() to anon, authenticated;
