-- Objective 3 harness (plan Q44): how SOS reached the server.
--
-- sos_delivery_report(from, to) returns, for SOS received in the period and
-- grouped by the channel that delivered them first (app, sms, bleRelay):
-- how many, and the delay from the phone's capture time to the server's
-- receipt (median, 95th percentile, maximum, and how many arrived within 1,
-- 5, and 15 minutes). The app, SMS, and relay copies of one SOS share its
-- client UUID, so each SOS is counted once, on the tier that got there
-- first. A capture time after the receipt (the phone's clock is ahead)
-- counts as no delay.
--
-- The trial team counts the attempts on the phones; A4 divides. Which
-- window counts as a success is Q44 (still open), so all three are shown.
--
-- Also from sos_relay_log: how many relayed packets were uploaded, for how
-- many SOS, and the most hops one travelled.
--
-- Admins only. The same definitions as sosDelivery() in packages/shared
-- (the mock, which has no relay log).

create or replace function public.sos_delivery_report(p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  result jsonb;
begin
  perform private.require_admin();
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '400 days' then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  with d as (
    select i.channel,
      greatest(extract(epoch from i.received_at - i.captured_at), 0)::double precision as delay_s
    from public.incident_report i
    where i.origin = 'sos' and i.received_at >= p_from and i.received_at < p_to
  )
  select jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'channels', coalesce(
      (select jsonb_agg(jsonb_build_object(
           'channel', x.channel, 'count', x.n,
           'median_s', x.m, 'p95_s', x.p, 'max_s', x.mx,
           'within_60', x.w1, 'within_300', x.w5, 'within_900', x.w15)
         order by array_position(array['app', 'sms', 'bleRelay', 'webForm'], x.channel), x.channel)
         from (select d.channel, count(*) as n,
                      percentile_cont(0.5) within group (order by d.delay_s) as m,
                      percentile_cont(0.95) within group (order by d.delay_s) as p,
                      max(d.delay_s) as mx,
                      count(*) filter (where d.delay_s <= 60) as w1,
                      count(*) filter (where d.delay_s <= 300) as w5,
                      count(*) filter (where d.delay_s <= 900) as w15
                 from d group by d.channel) x),
      '[]'::jsonb),
    'relay_uploads', (select count(*) from public.sos_relay_log l
                       where l.received_at >= p_from and l.received_at < p_to),
    'relayed_sos', (select count(distinct l.client_uuid) from public.sos_relay_log l
                     where l.received_at >= p_from and l.received_at < p_to),
    'relay_max_hops', (select max(l.hops) from public.sos_relay_log l
                        where l.received_at >= p_from and l.received_at < p_to)
  ) into result;
  return result;
end $$;

revoke execute on function public.sos_delivery_report(timestamptz, timestamptz) from public, anon;
grant execute on function public.sos_delivery_report(timestamptz, timestamptz) to authenticated;
