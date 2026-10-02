-- The sending side of alerts (FR6, plan section 12): what the send-alerts
-- Edge Function needs to work through queued deliveries. Only the service
-- role can call these; the apps cannot.
--
-- - claim_alert_deliveries(): takes the queued push, SMS, and Facebook rows
--   (and any stuck in "sending" for 10 minutes) and marks them "sending",
--   so two runs never send the same alert twice.
-- - alert_sms_recipients(): the numbers of registered residents in the
--   alert's barangays (everyone when the alert is for all of Manila).
-- - alert_sms_budget(): the daily cap on alert texts (an A3 setting) and
--   how many are left today.
-- - finish_alert_delivery(): the outcome and the counts for the log.
--
-- Everything here is added; the only change is one more allowed status.

alter table public.alert_delivery drop constraint alert_delivery_status_check;
alter table public.alert_delivery add constraint alert_delivery_status_check
  check (status in ('queued', 'sending', 'sent', 'failed', 'off', 'simulated', 'notSetUp', 'ended'));
comment on column public.alert_delivery.status is
  'queued: waiting for the sender. sending: claimed by a run. sent, failed: the outcome. off: the channel was switched off. simulated: never sent outside the apps. notSetUp: no provider yet. ended: the alert expired before it was sent.';

-- A spending cap (plan section 12): each text costs Semaphore credit.
insert into public.app_setting (key, category, value, min_value, max_value, description) values
  ('channels.sms_daily_cap', 'channels', '500', 0, 100000,
   'Most alert texts sent in one day (Manila time)');

create or replace function public.claim_alert_deliveries()
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  result jsonb;
begin
  with picked as (
    select d.delivery_id
      from public.alert_delivery d
     where d.channel <> 'app'
       and (d.status = 'queued'
            or (d.status = 'sending' and d.updated_at < now() - interval '10 minutes'))
     order by d.delivery_id
     limit 50
     for update skip locked
  ), claimed as (
    update public.alert_delivery d
       set status = 'sending', updated_at = now()
      from picked p
     where d.delivery_id = p.delivery_id
    returning d.delivery_id, d.alert_id, d.channel
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'delivery_id', c.delivery_id,
           'channel', c.channel,
           'alert', jsonb_build_object(
             'alert_id', a.alert_id,
             'level', a.level,
             'title', a.title,
             'body', a.body,
             'barangays', a.barangays,
             'ended', a.expires_at is not null and a.expires_at <= now())
         ) order by c.delivery_id), '[]'::jsonb)
    into result
    from claimed c
    join public.public_alert a on a.alert_id = c.alert_id;
  return result;
end $$;

-- Full numbers: for the sender only, never for a client.
create or replace function public.alert_sms_recipients(p_alert_id text)
returns text[]
language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(distinct r.contact_number), '{}'::text[])
    from public.manila_resident r
    join public.public_alert a on a.alert_id = p_alert_id
   where btrim(coalesce(r.contact_number, '')) <> ''
     and (cardinality(a.barangays) = 0 or r.barangay = any (a.barangays))
$$;

create or replace function public.alert_sms_budget()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'cap', x.cap,
    'sent_today', x.sent,
    'left', greatest(x.cap - x.sent, 0))
  from (
    select coalesce(private.setting_number('channels.sms_daily_cap'), 0)::int as cap,
           (select coalesce(sum(d.delivered), 0)::int
              from public.alert_delivery d
             where d.channel = 'sms' and d.status in ('sent', 'failed')
               and (d.updated_at at time zone 'Asia/Manila')::date
                   = (now() at time zone 'Asia/Manila')::date) as sent
  ) x
$$;

create or replace function public.finish_alert_delivery(
  p_delivery_id bigint,
  p_status text,
  p_recipients int default null,
  p_delivered int default null,
  p_failed int default null,
  p_detail text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_status is null or p_status not in ('sent', 'failed', 'notSetUp', 'ended') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  update public.alert_delivery
     set status = p_status, recipients = p_recipients, delivered = p_delivered,
         failed = p_failed, detail = left(p_detail, 300), updated_at = now()
   where delivery_id = p_delivery_id and status = 'sending';
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
end $$;

revoke execute on function
  public.claim_alert_deliveries(), public.alert_sms_recipients(text), public.alert_sms_budget(),
  public.finish_alert_delivery(bigint, text, int, int, int, text)
from public, anon, authenticated;
grant execute on function
  public.claim_alert_deliveries(), public.alert_sms_recipients(text), public.alert_sms_budget(),
  public.finish_alert_delivery(bigint, text, int, int, int, text)
to service_role;
