-- Objective 3's success window is 3 minutes (Joshua, 2026-11-12: "can we
-- make it 3 minutes? because in emergency time is really crucial"; plan
-- Q44 decided). sos_delivery_report adds within_180 beside the 1, 5, and
-- 15-minute counts it already gives; everything else is unchanged.

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
           'within_60', x.w1, 'within_180', x.w3, 'within_300', x.w5, 'within_900', x.w15)
         order by array_position(array['app', 'sms', 'bleRelay', 'webForm'], x.channel), x.channel)
         from (select d.channel, count(*) as n,
                      percentile_cont(0.5) within group (order by d.delay_s) as m,
                      percentile_cont(0.95) within group (order by d.delay_s) as p,
                      max(d.delay_s) as mx,
                      count(*) filter (where d.delay_s <= 60) as w1,
                      count(*) filter (where d.delay_s <= 180) as w3,
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
