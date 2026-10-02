-- Push notifications (FR6, FR14, Process 4.0; plan part 7) through Firebase
-- Cloud Messaging. Three kinds:
--
-- - Alerts (weather warnings, advisories): sent to FCM topics, not to
--   devices one by one. The app subscribes a resident to "manila" and to
--   their barangay's topic; send-alerts sends the alert's `push` delivery
--   (alert_delivery, already queued) to the matching topics.
-- - Rescue confirmations: each new rescue_confirmation row queues a push to
--   the resident's own phones.
-- - New assignments: each new dispatch row queues a push to the phones of
--   the responders on that unit, so a phone in a pocket still rings.
--
-- push_device holds the phones' FCM tokens (registered by the app after
-- sign-in); push_message is the queue of personal pushes. Neither can be
-- read by any client; only the sender (service role) reads them.
--
-- Everything here is added; nothing existing changes.

create table public.push_device (
  token text primary key check (length(token) between 20 and 4096),
  user_id uuid not null references auth.users (id) on delete cascade,
  platform text not null default 'android' check (platform in ('android')),
  created_at timestamptz not null default now(),
  -- The app registers again on every start; the sender uses only phones
  -- seen in the last 90 days.
  updated_at timestamptz not null default now(),
  -- Set when the phone signed out or FCM said the token no longer exists;
  -- such a phone gets nothing until it registers again.
  forgotten_at timestamptz
);
comment on table public.push_device is
  'FCM tokens of signed-in phones (push notifications). Service role only.';
create index push_device_user_idx on public.push_device (user_id);
alter table public.push_device enable row level security;
-- No policies and no grants: only the service role.

create table public.push_message (
  message_id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('rescue', 'assignment')),
  title text not null,
  body text not null,
  -- Values the app reads when the notification is tapped (strings only).
  data jsonb not null default '{}',
  -- queued: waiting for the sender. sending: claimed by a run. sent: FCM
  -- accepted it for at least one phone. failed: for none. noDevice: the
  -- account has no phone registered. off: push was switched off on A3.
  -- notSetUp: no Firebase key on the sender. expired: still waiting
  -- after 30 minutes, so not sent.
  status text not null default 'queued' check (status in (
    'queued', 'sending', 'sent', 'failed', 'noDevice', 'off', 'notSetUp', 'expired'
  )),
  devices int check (devices >= 0),
  delivered int check (delivered >= 0),
  detail text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.push_message is
  'Personal pushes waiting to go or already sent (rescue confirmations, new assignments). Service role only.';
create index push_message_queue_idx on public.push_message (status) where status in ('queued', 'sending');
alter table public.push_message enable row level security;
-- No policies and no grants: only the service role.

-- ------------------------------------------------------------ the phones

-- Called by the app after sign-in and whenever FCM gives it a new token.
-- A token that belonged to another account on the same phone moves to
-- this one.
create or replace function public.register_push_device(p_token text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  v_token text := btrim(coalesce(p_token, ''));
begin
  if me is null then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if length(v_token) < 20 or length(v_token) > 4096 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  insert into public.push_device (token, user_id)
  values (v_token, me)
  on conflict (token) do update
    set user_id = excluded.user_id, updated_at = now(), forgotten_at = null;
end $$;

-- Called by the app before it signs out, so this phone stops getting the
-- account's pushes. Only the caller's own token is marked.
create or replace function public.forget_push_device(p_token text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  update public.push_device d
     set forgotten_at = now()
   where d.token = btrim(coalesce(p_token, '')) and d.user_id = me and d.forgotten_at is null;
end $$;

-- ------------------------------------------------------------ queueing

create or replace function private.push_status()
returns text
language sql stable security definer set search_path = ''
as $$ select case when private.setting_flag('channels.push') then 'queued' else 'off' end $$;

-- A rescue confirmation (FR6) goes to the resident's phones too. The words
-- match the app's ("About your SOS" on the Alerts tab).
create or replace function private.queue_rescue_push()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid;
  v_unit text := nullif(btrim(coalesce(new.unit_call_sign, '')), '');
  v_title text;
  v_body text;
begin
  select r.auth_user_id into v_user
    from public.manila_resident r where r.manila_resident_id = new.manila_resident_id;
  if v_user is null then
    return new;
  end if;
  case new.kind
    when 'assigned' then
      v_title := 'A rescue team is coming';
      v_body := coalesce(v_unit, 'A rescue team')
        || ' has been sent to your location. Stay where you are if it is safe.';
    when 'onScene' then
      v_title := 'The rescue team has arrived';
      v_body := case when v_unit is null then 'The rescue team is at your location.'
                     else v_unit || ' is at your location.' end;
    else
      v_title := 'Your SOS was closed';
      v_body := 'MDRRMD closed this SOS. If you still need help, send a new SOS.';
  end case;
  insert into public.push_message (user_id, kind, title, body, data, status)
  values (v_user, 'rescue', v_title, v_body,
          jsonb_build_object('type', 'rescue', 'incident_id', new.incident_id,
                             'confirmation_id', new.confirmation_id::text),
          private.push_status());
  return new;
end $$;

create trigger rescue_confirmation_push
  after insert on public.rescue_confirmation
  for each row execute function private.queue_rescue_push();

-- A new dispatch goes to the phones of the responders on that unit, so an
-- assignment rings even with the app closed (plan part 7).
create or replace function private.queue_assignment_push()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  inc public.incident_report;
  v_type text;
begin
  select * into inc from public.incident_report i where i.incident_id = new.incident_id;
  v_type := case coalesce(inc.emergency_type, inc.suggested_type)
              when 'flood' then 'Flood'
              when 'fire' then 'Fire'
              when 'medical' then 'Medical'
              when 'structural' then 'Structural'
              else 'Type not confirmed' end;
  insert into public.push_message (user_id, kind, title, body, data, status)
  select s.id, 'assignment',
         'New assignment: ' || new.incident_id,
         v_type || ' · ' || inc.barangay || ', ' || inc.district || '. Open S.A.G.I.P. to accept.',
         jsonb_build_object('type', 'assignment', 'incident_id', new.incident_id),
         private.push_status()
    from public.staff s
   where s.role = 'responder' and s.unit_id = new.unit_id and s.deactivated_at is null;
  return new;
end $$;

create trigger dispatch_push
  after insert on public.dispatch
  for each row execute function private.queue_assignment_push();

-- ------------------------------------------------------------ the sender

-- The phones a push goes to: the account's five most recently seen, and
-- only those seen in the last 90 days and not forgotten. Old rows stay;
-- how long they are kept belongs to the data retention rule still to be
-- decided.
create or replace function private.push_tokens(p_user uuid)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(x.token order by x.updated_at desc), '[]'::jsonb)
    from (select d.token, d.updated_at from public.push_device d
           where d.user_id = p_user and d.forgotten_at is null
             and d.updated_at > now() - interval '90 days'
           order by d.updated_at desc
           limit 5) x
$$;

-- Takes the pushes waiting to go (and any stuck in "sending" for 10
-- minutes), marks them "sending", and returns each with its phones'
-- tokens. A push for an account with no phone is closed as noDevice; one
-- still waiting after 30 minutes as expired.
create or replace function public.claim_push_messages()
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  result jsonb;
begin
  update public.push_message m
     set status = 'expired', detail = 'Not sent within 30 minutes', updated_at = now()
   where m.status = 'queued' and m.created_at < now() - interval '30 minutes';

  update public.push_message m
     set status = 'noDevice', devices = 0, updated_at = now()
   where m.status = 'queued'
     and jsonb_array_length(private.push_tokens(m.user_id)) = 0;

  with picked as (
    select m.message_id
      from public.push_message m
     where m.status = 'queued'
        or (m.status = 'sending' and m.updated_at < now() - interval '10 minutes')
     order by m.message_id
     limit 100
     for update skip locked
  ), claimed as (
    update public.push_message m
       set status = 'sending', updated_at = now()
      from picked p
     where m.message_id = p.message_id
    returning m.message_id, m.user_id, m.kind, m.title, m.body, m.data
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'message_id', c.message_id,
           'kind', c.kind,
           'title', c.title,
           'body', c.body,
           'data', c.data,
           'tokens', private.push_tokens(c.user_id)
         ) order by c.message_id), '[]'::jsonb)
    into result
    from claimed c;
  return result;
end $$;

create or replace function public.finish_push_message(
  p_message_id bigint,
  p_status text,
  p_devices int default null,
  p_delivered int default null,
  p_detail text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_status is null or p_status not in ('sent', 'failed', 'notSetUp', 'noDevice') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  update public.push_message
     set status = p_status, devices = p_devices, delivered = p_delivered,
         detail = left(p_detail, 300), updated_at = now()
   where message_id = p_message_id and status = 'sending';
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
end $$;

-- FCM said these tokens no longer exist (the app was removed, or the phone
-- signed out): stop sending to them.
create or replace function public.forget_push_tokens(p_tokens text[])
returns int
language sql security definer set search_path = ''
as $$
  with gone as (
    update public.push_device d
       set forgotten_at = now()
     where d.token = any (coalesce(p_tokens, '{}'::text[])) and d.forgotten_at is null
    returning 1
  )
  select count(*)::int from gone
$$;

-- ------------------------------------------------------------ privileges

revoke execute on function
  private.push_status(), private.queue_rescue_push(), private.queue_assignment_push(),
  private.push_tokens(uuid)
from public, anon, authenticated;

revoke execute on function
  public.register_push_device(text), public.forget_push_device(text)
from public, anon;
grant execute on function
  public.register_push_device(text), public.forget_push_device(text)
to authenticated;

revoke execute on function
  public.claim_push_messages(), public.finish_push_message(bigint, text, int, int, text),
  public.forget_push_tokens(text[])
from public, anon, authenticated;
grant execute on function
  public.claim_push_messages(), public.finish_push_message(bigint, text, int, int, text),
  public.forget_push_tokens(text[])
to service_role;
