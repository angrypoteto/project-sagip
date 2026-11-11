-- Objective 3 field trial: what the server received, by tier.
-- Replace the two times with the trial's start and end (Manila time).
-- Counts only; no names, numbers, or positions.

with trial as (
  select i.incident_id, i.channel, i.captured_at, i.received_at,
         extract(epoch from i.received_at - i.captured_at) as delay_s
    from public.incident_report i
   where i.origin = 'sos'
     and not i.is_simulated
     and i.received_at >= timestamptz '2026-11-15 09:00 Asia/Manila'
     and i.received_at <  timestamptz '2026-11-15 12:00 Asia/Manila'
)
select channel,
       count(*)                                                   as delivered,
       round(percentile_cont(0.5) within group (order by greatest(delay_s, 0))::numeric, 1) as median_delay_s,
       round(max(greatest(delay_s, 0))::numeric, 1)               as longest_delay_s,
       count(*) filter (where delay_s <= 60)                      as within_1_min,
       count(*) filter (where delay_s <= 180)                     as within_3_min,  -- the success window
       count(*) filter (where delay_s <= 300)                     as within_5_min,
       count(*) filter (where delay_s <= 900)                     as within_15_min
  from trial
 group by channel
 order by delivered desc;

-- One row per SOS, to match against the tally sheet:
-- select incident_id, channel, captured_at at time zone 'Asia/Manila' as pressed,
--        received_at at time zone 'Asia/Manila' as on_server, round(delay_s) as delay_s
--   from trial order by captured_at;
