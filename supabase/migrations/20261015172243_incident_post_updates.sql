-- Incident posts follow the incident (Joshua, 2026-10-16): "post it even
-- though it is not verified but put it on unverified, and then the unit
-- that has been deployed will confirm it"; "edit the post to confirmed, and
-- if not, something like fake news" (worded "False alarm", which does not
-- accuse the person who reported it).
--
-- One post per incident, edited in place on the Page:
-- - Unverified: a flood, fire, or structural SOS gets a post when a unit is
--   assigned to it, marked unverified. A confirmed incident (verified by a
--   dispatcher, by the responder on scene, or a crowd cluster) is posted
--   as confirmed even with no unit yet.
-- - Confirmed: the same post is edited when the incident is verified.
-- - False alarm: edited when it is marked a false report, the responder
--   answers that it is not a real emergency, or the SOS is cancelled. One
--   that never reached the Page is withdrawn instead.
-- - Resolved: a confirmed post gets an update line.
-- Still never: medical, anything not flood, fire, or structural (crime is
-- outside the study's scope), simulated incidents, anything but the
-- district.

alter table public.incident_post
  add column stage text not null default 'confirmed'
    check (stage in ('unverified', 'confirmed', 'falseAlarm')),
  add column fb_post_id text,
  add column posted_message text,
  add column confirmed_at timestamptz;
comment on column public.incident_post.message is
  'The words the post should show now; re-sent as an edit when they change.';
comment on column public.incident_post.posted_message is
  'The words the Page last accepted.';
-- The rows so far were all made confirmed.
update public.incident_post set confirmed_at = created_at where confirmed_at is null;

create or replace function private.incident_post_text(
  p_type text, p_district text, p_stage text,
  p_reported timestamptz, p_confirmed timestamptz, p_resolved timestamptz)
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
           when 'falseAlarm' then
             'False alarm: no ' || what || ' in ' || place || '.' || E'\n\n'
             || 'The report from ' || reported || ' was checked by MDRRMD and no emergency was found. '
             || 'Thank you for staying alert.'
           else
             'Confirmed ' || what || ' in ' || place || '.' || E'\n\n'
             || 'Reported at ' || reported
             || coalesce(', confirmed at ' || confirmed, '')
             || '. Responders have been notified. Avoid the area and keep the roads clear for rescue vehicles.'
             || coalesce(E'\n\n' || 'Update ' || resolved || ': responders have finished. The area is clear.', '')
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
    when new.false_report or new.cancelled or new.real_emergency is false then 'falseAlarm'
    when new.verification_method is not null or new.origin = 'crowdCluster' then 'confirmed'
    else 'unverified'
  end;
  select * into p from public.incident_post x where x.incident_id = new.incident_id;

  if p.post_id is null then
    -- A new post: a confirmed incident, or an unverified one a unit was
    -- sent to. Never one already closed or false.
    if v_stage = 'falseAlarm' or new.status = 'resolved'
       or (v_stage = 'unverified' and new.assigned_unit_id is null) then
      return null;
    end if;
    v_confirmed := case when v_stage = 'confirmed' then now() end;
    insert into public.incident_post (incident_id, stage, confirmed_at, message, status)
    values (
      new.incident_id, v_stage, v_confirmed,
      private.incident_post_text(v_type, new.district, v_stage, new.received_at, v_confirmed, null),
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
  v_message := private.incident_post_text(
    v_type, new.district, v_stage, new.received_at, v_confirmed,
    case when v_stage = 'confirmed' and new.status = 'resolved' then coalesce(new.resolved_at, now()) end);
  if v_stage = 'falseAlarm' and p.fb_post_id is null then
    -- Never reached the Page: nothing to correct.
    update public.incident_post
       set stage = v_stage, message = v_message, status = 'withdrawn',
           detail = 'False alarm before it was posted', updated_at = now()
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

drop trigger incident_report_post on public.incident_report;
create trigger incident_report_post
  after insert or update of verification_method, emergency_type, suggested_type, origin,
    assigned_unit_id, status, false_report, cancelled, real_emergency
  on public.incident_report
  for each row execute function private.queue_incident_post();

-- An edit is queued by an update, not an insert: wake the sender then too.
create function private.wake_sender_for_incident_post_edits()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (select 1 from changed c where c.status = 'queued') then
    perform private.call_incident_poster();
  end if;
  return null;
end $$;

create trigger incident_post_edit_wake_sender
  after update on public.incident_post
  referencing new table as changed
  for each statement execute function private.wake_sender_for_incident_post_edits();

-- The sender is also told which Page post to edit.
create or replace function public.claim_incident_posts()
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  result jsonb;
begin
  with picked as (
    select p.post_id from public.incident_post p
     where p.status = 'queued'
        or (p.status = 'sending' and p.updated_at < now() - interval '10 minutes')
     order by p.post_id
     limit 20
     for update skip locked
  ), claimed as (
    update public.incident_post p
       set status = 'sending', updated_at = now()
      from picked k
     where p.post_id = k.post_id
    returning p.post_id, p.incident_id, p.message, p.fb_post_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'post_id', c.post_id, 'incident_id', c.incident_id,
           'message', c.message, 'fb_post_id', c.fb_post_id
         ) order by c.post_id), '[]'::jsonb)
    into result from claimed c;
  return result;
end $$;

-- The outcome of one claimed post or edit. [p_message] is the text that was
-- sent: when the incident changed again meanwhile, the post goes back in
-- the queue with the newer words.
create function public.record_incident_post(
  p_post_id bigint, p_status text, p_detail text default null,
  p_fb_post_id text default null, p_message text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_status not in ('sent', 'failed', 'notSetUp') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  update public.incident_post
     set status = case
           when p_status = 'sent' and p_message is distinct from message then 'queued'
           else p_status end,
         fb_post_id = coalesce(fb_post_id, nullif(btrim(coalesce(p_fb_post_id, '')), '')),
         posted_message = case when p_status = 'sent' then p_message else posted_message end,
         detail = left(p_detail, 300),
         updated_at = now()
   where post_id = p_post_id and status = 'sending';
end $$;

revoke execute on function
  private.incident_post_text(text, text, text, timestamptz, timestamptz, timestamptz),
  private.wake_sender_for_incident_post_edits(),
  public.record_incident_post(bigint, text, text, text, text)
from public, anon, authenticated;
revoke execute on function public.finish_incident_post(bigint, text, text) from service_role;
grant execute on function public.record_incident_post(bigint, text, text, text, text) to service_role;
