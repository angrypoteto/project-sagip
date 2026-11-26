-- Post an emergency to the Facebook Page as soon as it arrives (Joshua,
-- 2026-11-26: "I want it to be published, then when it is confirmed it will
-- just be edited").
--
-- Before: an unverified flood, fire, or structural SOS was posted only once a
-- unit was assigned (incident_post_updates, 2026-10-16). Now it is posted at
-- once, marked "Unverified report", and the same post is edited as before:
-- Confirmed when verified, False alarm when marked false or not a real
-- emergency, Resolved when closed. Everything else is unchanged: one post per
-- incident, the district only, never medical, never simulated, held back while
-- the A3 switch is off, and a report withdrawn before it reached the Page is
-- not posted.

create or replace function private.queue_incident_post()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_type text := coalesce(new.emergency_type, new.suggested_type);
  p public.incident_post;
  v_stage text;
  v_confirmed timestamptz;
  v_message text;
begin
  if v_type is null or v_type not in ('flood', 'fire', 'structural') then
    return null;
  end if;
  v_stage := case
    when new.false_report or new.real_emergency is false then 'falseAlarm'
    when new.verification_method is not null or new.origin = 'crowdCluster' then 'confirmed'
    when new.cancelled then 'withdrawn'
    else 'unverified'
  end;
  select * into p from public.incident_post x where x.incident_id = new.incident_id;

  if p.post_id is null then
    -- A new post as soon as the incident arrives (unverified or confirmed).
    -- Never one already closed, false, or withdrawn.
    if v_stage in ('falseAlarm', 'withdrawn') or new.status = 'resolved' then
      return null;
    end if;
    v_confirmed := case when v_stage = 'confirmed' then now() end;
    insert into public.incident_post (incident_id, stage, confirmed_at, message, status)
    values (
      new.incident_id, v_stage, v_confirmed,
      private.incident_post_words(v_type, new.district, v_stage, new.received_at, v_confirmed, null, false),
      case
        when new.is_simulated then 'simulated'
        when not coalesce(private.setting_flag('channels.facebook_incidents'), false) then 'off'
        else 'queued'
      end)
    on conflict (incident_id) do nothing;
    return null;
  end if;

  -- An existing post follows the incident. One held back (off, simulated)
  -- or withdrawn stays as it is.
  if p.status in ('off', 'simulated', 'withdrawn') then
    return null;
  end if;
  v_confirmed := case when v_stage = 'confirmed' then coalesce(p.confirmed_at, now()) end;
  v_message := private.incident_post_words(
    v_type, new.district, v_stage, new.received_at, v_confirmed,
    case when v_stage = 'confirmed' and new.status = 'resolved' then coalesce(new.resolved_at, now()) end,
    new.cancelled);
  if v_stage in ('falseAlarm', 'withdrawn') and p.fb_post_id is null then
    -- Never reached the Page: nothing to correct.
    update public.incident_post
       set stage = v_stage, message = v_message, status = 'withdrawn',
           detail = case when v_stage = 'falseAlarm' then 'False alarm before it was posted'
                         else 'Withdrawn by the resident before it was posted' end,
           updated_at = now()
     where post_id = p.post_id;
  elsif v_message is distinct from p.message then
    update public.incident_post
       set stage = v_stage, confirmed_at = coalesce(v_confirmed, p.confirmed_at),
           message = v_message,
           status = case when p.status = 'sending' then 'sending' else 'queued' end,
           updated_at = now()
     where post_id = p.post_id;
  end if;
  return null;
end $$;
