-- Advisories from the dashboard (D10; FR6, FR14).
--
-- A dispatcher or an administrator issues an advisory for residents: an
-- MDRRMD notice, or one relayed from PAGASA, PHIVOLCS, or EFCOS (the feeds
-- are not connected, so relaying is by hand). It appears in the apps at
-- once, and the delivery log queues it on each channel that is switched
-- on, exactly like an alert from the threshold engine. While simulation
-- mode is on, an advisory is marked simulated and is never texted or
-- posted. Ending an advisory hides it from the apps. Both are audited.
--
-- Everything here is added; the audit log only gains two action types.

alter table public.audit_log drop constraint audit_log_action_type_check;
alter table public.audit_log add constraint audit_log_action_type_check check (action_type in (
  'verified', 'markedFalseReport', 'typeConfirmed', 'unitAssigned', 'unitReassigned',
  'statusChanged', 'resolved', 'smsCheckSent', 'contactViewed', 'settingChanged',
  'unitAdded', 'unitEdited', 'unitRetired', 'unitRestored', 'rosterChanged',
  'accountCreated', 'accountUpdated', 'accountDeactivated', 'accountReactivated',
  'passwordReset', 'residentSuspended', 'residentRestored', 'weatherSimulated',
  'alertIssued', 'alertEnded'
));

create or replace function public.issue_alert(
  p_source text,
  p_level text,
  p_title text,
  p_body text,
  p_guidance text[] default '{}',
  p_barangays text[] default '{}'
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  v_title text := btrim(coalesce(p_title, ''));
  v_body text := btrim(coalesce(p_body, ''));
  steps text[];
  areas text[];
  simulated boolean := private.setting_flag('demo.simulation');
  new_id text;
begin
  if p_source is null or p_source not in ('mdrrmd', 'pagasa', 'phivolcs', 'efcos')
     or p_level is null or p_level not in ('info', 'warning', 'critical')
     or length(v_title) = 0 or length(v_title) > 120
     or length(v_body) = 0 or length(v_body) > 1000 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  -- Blank steps are dropped; the order is kept.
  select coalesce(array_agg(btrim(g.step) order by g.n), '{}'::text[]) into steps
    from unnest(coalesce(p_guidance, '{}'::text[])) with ordinality as g(step, n)
   where btrim(coalesce(g.step, '')) <> '';
  select coalesce(array_agg(distinct btrim(b)), '{}'::text[]) into areas
    from unnest(coalesce(p_barangays, '{}'::text[])) b
   where btrim(coalesce(b, '')) <> '';
  if cardinality(steps) > 8
     or exists (select 1 from unnest(steps) s where length(s) > 200)
     -- Only barangays the system knows; an empty list is all of Manila.
     or exists (select 1 from unnest(areas) a
                 where not exists (select 1 from public.barangay x where x.name = a)) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  insert into public.public_alert (source, level, title, body, guidance, barangays, is_simulated)
  values (p_source, p_level, v_title, v_body, steps, areas, simulated)
  returning alert_id into new_id;
  perform private.audit_admin(me, 'alertIssued', 'public_alert', new_id,
    p_level || ': ' || v_title || case when simulated then ' (simulated)' else '' end);
  return new_id;
end $$;

-- Ends an alert that is still showing. Ending one that already ended does
-- nothing; a delivery still waiting is skipped by the sender.
create or replace function public.end_alert(p_alert_id text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  a public.public_alert;
begin
  select * into a from public.public_alert x where x.alert_id = p_alert_id for update;
  if a.alert_id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if a.expires_at is not null and a.expires_at <= now() then
    return;
  end if;
  update public.public_alert set expires_at = now() where alert_id = a.alert_id;
  perform private.audit_admin(me, 'alertEnded', 'public_alert', a.alert_id, a.title);
end $$;

revoke execute on function
  public.issue_alert(text, text, text, text, text[], text[]), public.end_alert(text)
from public, anon;
grant execute on function
  public.issue_alert(text, text, text, text, text[], text[]), public.end_alert(text)
to authenticated;
