-- A cancelled SOS is not a false alarm (2026-10-16). INC-0165, a verified
-- flood, was closed after the resident answered "I'm safe now", and its
-- post was edited to "False alarm: ... no emergency was found", which was
-- wrong. Now:
-- - "False alarm" only when a dispatcher marks a false report or the
--   responder answers on scene that it is not a real emergency.
-- - A confirmed incident the resident cancels stays confirmed, with the
--   update "the person who asked for help is safe".
-- - An unverified report the resident cancels says it was withdrawn by the
--   person who made it (or is not posted at all if it never was).

alter table public.incident_post drop constraint incident_post_stage_check;
alter table public.incident_post add constraint incident_post_stage_check
  check (stage in ('unverified', 'confirmed', 'falseAlarm', 'withdrawn'));

create function private.incident_post_words(
  p_type text, p_district text, p_stage text, p_reported timestamptz,
  p_confirmed timestamptz, p_resolved timestamptz, p_resident_safe boolean)
returns text
language sql stable security definer set search_path = ''
as $$
  with t as (
    select case p_type when 'flood' then 'flooding' when 'fire' then 'fire' else 'structural damage' end as what,
           coalesce(nullif(btrim(p_district), ''), 'Manila') as place,
           to_char(p_reported at time zone 'Asia/Manila', 'FMHH12:MI AM, FMMonth FMDD') as reported,
           to_char(p_confirmed at time zone 'Asia/Manila', 'FMHH12:MI AM') as confirmed,
           to_char(p_resolved at time zone 'Asia/Manila', 'FMHH12:MI AM') as resolved,
           case when coalesce(private.setting_text('contact.hotline'), '') = '' then '.'
                else ' at ' || private.setting_text('contact.hotline') || '.' end as hotline
  )
  select case p_stage
           when 'unverified' then
             'Unverified report: possible ' || what || ' in ' || place || '.' || E'\n\n'
             || 'Reported at ' || reported || '. MDRRMD responders are on the way to check. '
             || 'Avoid the area if you can and keep the roads clear.'
           when 'withdrawn' then
             'Update: report withdrawn.' || E'\n\n'
             || 'The report of possible ' || what || ' in ' || place || ' from ' || reported
             || ' was withdrawn by the person who made it. No response is needed.'
           when 'falseAlarm' then
             'False alarm: no ' || what || ' in ' || place || '.' || E'\n\n'
             || 'The report from ' || reported || ' was checked by MDRRMD and no emergency was found. '
             || 'Thank you for staying alert.'
           else
             'Confirmed ' || what || ' in ' || place || '.' || E'\n\n'
             || 'Reported at ' || reported
             || coalesce(', confirmed at ' || confirmed, '')
             || '. Responders have been notified. Avoid the area and keep the roads clear for rescue vehicles.'
             || coalesce(E'\n\n' || 'Update ' || resolved
                  || case when p_resident_safe
                       then ': the person who asked for help is safe. No further response is needed.'
                       else ': responders have finished. The area is clear.' end, '')
         end
         || E'\n\n'
         || 'Sent through S.A.G.I.P. For rescue, hold SOS in the S.A.G.I.P. app or call MDRRMD' || hotline
    from t
$$;

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
    -- A new post: a confirmed incident, or an unverified one a unit was
    -- sent to. Never one already closed, false, or withdrawn.
    if v_stage in ('falseAlarm', 'withdrawn') or new.status = 'resolved'
       or (v_stage = 'unverified' and new.assigned_unit_id is null) then
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

revoke execute on function
  private.incident_post_words(text, text, text, timestamptz, timestamptz, timestamptz, boolean)
from public, anon, authenticated;
