-- Two-way SMS check (FR8, D4 "Send SMS check"): the dispatcher's check now
-- really texts the SOS sender, and a YES or NO reply through the gateway
-- shows on the incident.
--
-- send_sms_check() queues one text to the resident's number (or, for an
-- SOS texted from an unknown number, the number it came from) in
-- sms_check; the sender (send-alerts, woken by a trigger) texts it from the
-- gateway SIM or Semaphore. When sms-intake receives a reply from that
-- number within two hours, record_sms_check_reply() adds an
-- `smsReplyReceived` event with the answer (YES or NO), which the drawer
-- shows; the dispatcher still decides. sms_check is service-role only (it
-- holds full numbers).

alter table public.sms_log drop constraint sms_log_kind_check;
alter table public.sms_log add constraint sms_log_kind_check
  check (kind in ('otp', 'alert', 'ack', 'inbound', 'rescue', 'check'));

create table public.sms_check (
  check_id bigint generated always as identity primary key,
  incident_id text not null references public.incident_report (incident_id) on delete cascade,
  to_number text not null,
  status text not null default 'queued'
    check (status in ('queued', 'sending', 'sent', 'failed', 'notSetUp', 'expired')),
  detail text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reply text check (reply in ('YES', 'NO')),
  replied_at timestamptz
);
comment on table public.sms_check is
  'SMS checks texted to SOS senders and their replies (FR8). Service role only.';
create index sms_check_incident_idx on public.sms_check (incident_id, created_at desc);
alter table public.sms_check enable row level security;
-- No policies: only the service role reads it.

-- The number an SOS can be checked on: the resident's, or the one an SMS
-- SOS came from.
create function private.sos_sender_number(p_incident_id text)
returns text
language sql stable security definer set search_path = ''
as $$
  select coalesce(
    (select r.contact_number from public.incident_report i
       join public.manila_resident r on r.manila_resident_id = i.manila_resident_id
      where i.incident_id = p_incident_id),
    (select l.to_number from public.sms_log l
      where l.kind = 'inbound' and l.status = 'received'
        and l.detail like p_incident_id || '%'
      order by l.log_id desc limit 1))
$$;

create or replace function public.send_sms_check(p_incident_id text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  inc public.incident_report := public._open_incident(p_incident_id);
  number text := private.sos_sender_number(inc.incident_id);
begin
  insert into public.incident_event (incident_id, kind, actor_name)
  values (inc.incident_id, 'smsCheckSent', me.display_name);
  insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id)
  values (me.id::text, me.display_name, me.role, 'smsCheckSent', 'incident_report', inc.incident_id);
  -- One text per two minutes per incident, whatever the clicks.
  if number is not null and not exists (
    select 1 from public.sms_check c
     where c.incident_id = inc.incident_id and c.created_at > now() - interval '2 minutes'
  ) then
    insert into public.sms_check (incident_id, to_number) values (inc.incident_id, number);
  end if;
end $$;

create function private.wake_sender_for_sms_checks()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (select 1 from added a where a.status = 'queued') then
    perform private.call_sender();
  end if;
  return null;
end $$;

create trigger sms_check_wake_sender
  after insert on public.sms_check
  referencing new table as added
  for each statement execute function private.wake_sender_for_sms_checks();

-- For the sender: the queued checks (stuck ones after 10 minutes again;
-- unsent after 30 minutes expire).
create function public.claim_sms_checks()
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  result jsonb;
begin
  update public.sms_check
     set status = 'expired', detail = 'Not sent within 30 minutes', updated_at = now()
   where status = 'queued' and created_at < now() - interval '30 minutes';
  with picked as (
    select c.check_id from public.sms_check c
     where c.status = 'queued'
        or (c.status = 'sending' and c.updated_at < now() - interval '10 minutes')
     order by c.check_id
     limit 50
     for update skip locked
  ), claimed as (
    update public.sms_check c
       set status = 'sending', updated_at = now()
      from picked p
     where c.check_id = p.check_id
    returning c.check_id, c.incident_id, c.to_number
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'check_id', c.check_id, 'incident_id', c.incident_id, 'to', c.to_number)
         order by c.check_id), '[]'::jsonb)
    into result from claimed c;
  return result;
end $$;

create function public.finish_sms_check(p_check_id bigint, p_status text, p_detail text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_status not in ('sent', 'failed', 'notSetUp') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  update public.sms_check
     set status = p_status, detail = left(p_detail, 300), updated_at = now()
   where check_id = p_check_id;
end $$;

-- For sms-intake: a text that may answer a check. YES (Y, OO, OPO) or NO
-- (N, HINDI) as its first word, from a number texted a check in the last
-- two hours. Returns {incident_id, answer}, or null when it is no answer.
create function public.record_sms_check_reply(p_from text, p_text text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  word text := upper(regexp_replace(btrim(coalesce(p_text, '')), '^([[:alpha:]]+).*$', '\1'));
  answer text;
  c public.sms_check;
begin
  answer := case
    when word in ('YES', 'Y', 'OO', 'OPO') then 'YES'
    when word in ('NO', 'N', 'HINDI') then 'NO'
  end;
  if answer is null then
    return null;
  end if;
  select * into c from public.sms_check s
   where private.phone_key(s.to_number) = private.phone_key(p_from)
     and s.status = 'sent' and s.replied_at is null
     and s.updated_at > now() - interval '2 hours'
   order by s.check_id desc
   limit 1
   for update;
  if c.check_id is null then
    return null;
  end if;
  update public.sms_check set reply = answer, replied_at = now() where check_id = c.check_id;
  insert into public.incident_event (incident_id, kind, detail)
  values (c.incident_id, 'smsReplyReceived', answer);
  return jsonb_build_object('incident_id', c.incident_id, 'answer', answer);
end $$;

revoke execute on function
  private.sos_sender_number(text), private.wake_sender_for_sms_checks()
from public, anon, authenticated;
revoke execute on function
  public.claim_sms_checks(), public.finish_sms_check(bigint, text, text),
  public.record_sms_check_reply(text, text)
from public, anon, authenticated;
grant execute on function
  public.claim_sms_checks(), public.finish_sms_check(bigint, text, text),
  public.record_sms_check_reply(text, text)
to service_role;
