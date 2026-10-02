-- Rescue confirmations (FR6, plan part 7): what a resident is told about
-- their own SOS as the rescue moves on.
--
-- A row is written when the SOS gets a unit ("assigned"), when the unit
-- arrives ("onScene"), and when the SOS is closed ("resolved"). The app
-- shows them on the Alerts tab (R7) and the resident marks them read.
--
-- - Only for an SOS with a registered resident. A crowd-report cluster has
--   no single sender, and a false report tells nobody anything.
-- - The first "assigned" of an SOS is also texted to the resident (one SMS
--   through Semaphore, sent by the send-alerts Edge Function): that is the
--   one a resident with no data connection needs. Arrival and closing are
--   in the app only. Like alerts, nothing is texted in simulation mode or
--   while the SMS channel is switched off on A3.
-- - A text still waiting after 30 minutes is not sent: it is no longer
--   news.
--
-- Everything here is added; nothing existing changes.

create table public.rescue_confirmation (
  confirmation_id bigint generated always as identity primary key,
  incident_id text not null references public.incident_report (incident_id) on delete cascade,
  manila_resident_id text not null
    references public.manila_resident (manila_resident_id) on delete cascade,
  kind text not null check (kind in ('assigned', 'onScene', 'resolved')),
  -- The unit at that moment, kept as text so the notice reads the same
  -- after a reassignment.
  unit_call_sign text,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  -- none: this kind is not texted. queued: waiting for the sender.
  -- sending: claimed by a run. sent, failed: the outcome. off: the SMS
  -- channel was switched off. simulated: simulation mode. notSetUp: no
  -- Semaphore key yet. expired: not sent within 30 minutes.
  sms_status text not null default 'none' check (sms_status in (
    'none', 'queued', 'sending', 'sent', 'failed', 'off', 'simulated', 'notSetUp', 'expired'
  )),
  sms_detail text,
  sms_updated_at timestamptz not null default now()
);
comment on table public.rescue_confirmation is
  'What a resident was told about their SOS (FR6): a unit assigned, on scene, closed. No numbers.';
create index rescue_confirmation_resident_idx
  on public.rescue_confirmation (manila_resident_id, created_at desc);
create index rescue_confirmation_incident_idx on public.rescue_confirmation (incident_id);
create index rescue_confirmation_queue_idx
  on public.rescue_confirmation (sms_status) where sms_status in ('queued', 'sending');

alter table public.rescue_confirmation enable row level security;
create policy "rescue confirmations: dispatchers, admins, or the resident"
  on public.rescue_confirmation
  for select to authenticated using (
    (select private.is_dispatcher())
    or manila_resident_id = (select private.current_resident_id())
  );
grant select on public.rescue_confirmation to authenticated;
alter publication supabase_realtime add table public.rescue_confirmation;

-- ------------------------------------------------------------ writing them

create or replace function private.confirm_rescue()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_kind text;
  v_call text;
  v_sms text := 'none';
begin
  if new.origin <> 'sos' or new.manila_resident_id is null or new.false_report then
    return new;
  end if;

  if new.status = 'resolved' and old.status <> 'resolved' then
    v_kind := 'resolved';
  elsif new.status = 'onScene' and old.status <> 'onScene' then
    v_kind := 'onScene';
  elsif new.assigned_unit_id is not null and new.status in ('assigned', 'enRoute')
        and (new.assigned_unit_id is distinct from old.assigned_unit_id
             -- An SOS texted from another SIM was just matched to its
             -- resident while a unit is already on the way.
             or old.manila_resident_id is null) then
    v_kind := 'assigned';
  else
    return new;
  end if;

  select u.call_sign into v_call
    from public.response_unit u where u.unit_id = new.assigned_unit_id;

  -- One text per SOS: the first unit assigned.
  if v_kind = 'assigned' and not exists (
       select 1 from public.rescue_confirmation c
        where c.incident_id = new.incident_id and c.kind = 'assigned') then
    v_sms := case
      when private.setting_flag('demo.simulation') then 'simulated'
      when not private.setting_flag('channels.sms') then 'off'
      else 'queued'
    end;
  end if;

  insert into public.rescue_confirmation
    (incident_id, manila_resident_id, kind, unit_call_sign, sms_status)
  values (new.incident_id, new.manila_resident_id, v_kind, v_call, v_sms);
  return new;
end $$;

create trigger incident_report_confirm_rescue
  after update on public.incident_report
  for each row execute function private.confirm_rescue();

-- ------------------------------------------------------------ the resident

-- R7: the resident has seen the confirmation. Marking it twice, or one
-- that is not theirs, changes nothing.
create or replace function public.mark_rescue_confirmation_read(p_confirmation_id bigint)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me text := private.current_resident_id();
begin
  if me is null then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  update public.rescue_confirmation
     set read_at = now()
   where confirmation_id = p_confirmation_id
     and manila_resident_id = me
     and read_at is null;
end $$;

-- ------------------------------------------------------------ the sender

-- Takes the texts waiting to go (and any stuck in "sending" for 10
-- minutes), marks them "sending", and returns each with the resident's
-- number. Full numbers: for the sender only, never for a client.
create or replace function public.claim_rescue_confirmations()
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  result jsonb;
begin
  update public.rescue_confirmation
     set sms_status = 'expired', sms_detail = 'Not sent within 30 minutes',
         sms_updated_at = now()
   where sms_status = 'queued' and created_at < now() - interval '30 minutes';

  with picked as (
    select c.confirmation_id
      from public.rescue_confirmation c
     where c.sms_status = 'queued'
        or (c.sms_status = 'sending' and c.sms_updated_at < now() - interval '10 minutes')
     order by c.confirmation_id
     limit 50
     for update skip locked
  ), claimed as (
    update public.rescue_confirmation c
       set sms_status = 'sending', sms_updated_at = now()
      from picked p
     where c.confirmation_id = p.confirmation_id
    returning c.confirmation_id, c.incident_id, c.kind, c.unit_call_sign, c.manila_resident_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'confirmation_id', c.confirmation_id,
           'incident_id', c.incident_id,
           'kind', c.kind,
           'unit_call_sign', c.unit_call_sign,
           'to', r.contact_number
         ) order by c.confirmation_id), '[]'::jsonb)
    into result
    from claimed c
    join public.manila_resident r on r.manila_resident_id = c.manila_resident_id;
  return result;
end $$;

create or replace function public.finish_rescue_confirmation(
  p_confirmation_id bigint,
  p_status text,
  p_detail text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_status is null or p_status not in ('sent', 'failed', 'notSetUp') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  update public.rescue_confirmation
     set sms_status = p_status, sms_detail = left(p_detail, 300), sms_updated_at = now()
   where confirmation_id = p_confirmation_id and sms_status = 'sending';
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
end $$;

-- ------------------------------------------------------------ privileges

revoke execute on function private.confirm_rescue() from public, anon, authenticated;

revoke execute on function public.mark_rescue_confirmation_read(bigint) from public, anon;
grant execute on function public.mark_rescue_confirmation_read(bigint) to authenticated;

revoke execute on function
  public.claim_rescue_confirmations(), public.finish_rescue_confirmation(bigint, text, text)
from public, anon, authenticated;
grant execute on function
  public.claim_rescue_confirmations(), public.finish_rescue_confirmation(bigint, text, text)
to service_role;
