-- Confirmed incidents on the MDRRMD Facebook Page (Joshua, 2026-10-13:
-- "every time an emergency or incident is pinged, post it on the Facebook
-- page so everyone is aware: the location, the time, and what it is").
--
-- What is posted, and what is not (RA 10173; FR7, FR8, FR15):
-- - Only a CONFIRMED incident: a dispatcher verified it, or three crowd
--   reports clustered. A single unverified SOS or report is never posted.
-- - Only a flood, a fire, or structural damage. A medical emergency is one
--   household's health and is not public.
-- - The district only ("Pandacan"), as Joshua asked: no barangay, street,
--   position, name, number, head count, or vulnerable status.
-- - Once per incident. A simulated incident is logged as simulated and
--   never posted. With the switch off on A3 it is logged as off.
--
-- The sender (the send-alerts function) claims the queue with the service
-- role and posts with the Page token it already has for alerts.

insert into public.app_setting (key, category, value, min_value, max_value, description) values
  ('channels.facebook_incidents', 'channels', 'false', null, null,
   'Post confirmed incidents on the MDRRMD Facebook Page');

create table public.incident_post (
  post_id bigint generated always as identity primary key,
  incident_id text not null unique
    references public.incident_report (incident_id) on delete cascade,
  -- The words posted, fixed when the incident was confirmed.
  message text not null,
  -- queued: waiting for the sender. sending: claimed by a run. sent,
  -- failed: the outcome. off: the switch was off. simulated: a simulated
  -- incident. notSetUp: no Page or token. withdrawn: the incident was
  -- marked false or cancelled before it was posted.
  status text not null check (status in
    ('queued', 'sending', 'sent', 'failed', 'off', 'simulated', 'notSetUp', 'withdrawn')),
  detail text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.incident_post is
  'One public post per confirmed flood, fire, or structural incident: type, district, time. No personal data.';
create index incident_post_status_idx on public.incident_post (status) where status = 'queued';

alter table public.incident_post enable row level security;
revoke all on public.incident_post from anon, authenticated;
create policy "incident posts: dispatchers and admins" on public.incident_post
  for select to authenticated using ((select private.is_dispatcher()));
grant select on public.incident_post to authenticated;

-- The post's words. Manila time; the hotline when one is set.
create function private.incident_post_text(p_type text, p_district text, p_at timestamptz)
returns text
language sql stable security definer set search_path = ''
as $$
  select 'Confirmed '
      || case p_type when 'flood' then 'flooding' when 'fire' then 'fire' else 'structural damage' end
      || ' in ' || coalesce(nullif(btrim(p_district), ''), 'Manila') || '.'
      || E'\n\n'
      || 'Confirmed at ' || to_char(p_at at time zone 'Asia/Manila', 'FMHH12:MI AM, FMMonth FMDD, YYYY')
      || '. Responders have been notified. Avoid the area and keep the roads clear for rescue vehicles.'
      || E'\n\n'
      || 'Sent through S.A.G.I.P. For rescue, hold SOS in the S.A.G.I.P. app or call MDRRMD'
      || case when coalesce(private.setting_text('contact.hotline'), '') = '' then '.'
              else ' at ' || private.setting_text('contact.hotline') || '.' end
$$;

create function private.queue_incident_post()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_type text := coalesce(new.emergency_type, new.suggested_type);
begin
  if v_type is null or v_type not in ('flood', 'fire', 'structural')
     or not (new.verification_method is not null or new.origin = 'crowdCluster')
     or new.status = 'resolved' or new.false_report or new.cancelled then
    return null;
  end if;
  insert into public.incident_post (incident_id, message, status)
  values (
    new.incident_id,
    private.incident_post_text(v_type, new.district, now()),
    case
      when new.is_simulated then 'simulated'
      when not coalesce(private.setting_flag('channels.facebook_incidents'), false) then 'off'
      else 'queued'
    end)
  on conflict (incident_id) do nothing;
  return null;
end $$;

create trigger incident_report_post
  after insert or update of verification_method, emergency_type, suggested_type, origin
  on public.incident_report
  for each row execute function private.queue_incident_post();

create function private.wake_sender_for_incident_posts()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (select 1 from added a where a.status = 'queued') then
    perform private.call_sender();
  end if;
  return null;
end $$;

create trigger incident_post_wake_sender
  after insert on public.incident_post
  referencing new table as added
  for each statement execute function private.wake_sender_for_incident_posts();

-- For the sender: the queued posts (stuck ones after 10 minutes again). A
-- post whose incident was marked false, cancelled, or resolved in the
-- meantime is withdrawn, not sent.
create function public.claim_incident_posts()
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  result jsonb;
begin
  update public.incident_post p
     set status = 'withdrawn', detail = 'The incident was closed or withdrawn before it was posted',
         updated_at = now()
    from public.incident_report i
   where i.incident_id = p.incident_id
     and p.status in ('queued', 'sending')
     and (i.false_report or i.cancelled or i.status = 'resolved');
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
    returning p.post_id, p.incident_id, p.message
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'post_id', c.post_id, 'incident_id', c.incident_id, 'message', c.message
         ) order by c.post_id), '[]'::jsonb)
    into result from claimed c;
  return result;
end $$;

-- The outcome of one claimed post, recorded once.
create function public.finish_incident_post(p_post_id bigint, p_status text, p_detail text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_status not in ('sent', 'failed', 'notSetUp') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  update public.incident_post
     set status = p_status, detail = left(p_detail, 300), updated_at = now()
   where post_id = p_post_id and status = 'sending';
end $$;

revoke execute on function
  private.incident_post_text(text, text, timestamptz), private.queue_incident_post(),
  private.wake_sender_for_incident_posts(),
  public.claim_incident_posts(), public.finish_incident_post(bigint, text, text)
from public, anon, authenticated;
grant execute on function
  public.claim_incident_posts(), public.finish_incident_post(bigint, text, text)
to service_role;
