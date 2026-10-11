-- After the SOS is sent: asking to cancel it, and where the resident is now
-- (plan Q10 and Q33; Joshua decided both on 2026-10-11).
--
-- Cancel SOS. A resident may ask to cancel their own SOS until the unit is
-- on scene, with a reason. The SOS stays on the board, marked "Resident
-- asked to cancel"; nothing is closed by the resident. A dispatcher closes
-- it (confirm_sos_cancel) or carries on, for example after calling back:
-- a cancel can be a mistake, or made under pressure. The resident may take
-- the request back (withdraw_sos_cancel).
--
-- Where the resident is now. While an SOS is open the app sends the
-- phone's position when it has moved (update_sos_location). The place the
-- SOS was sent from is never changed; the newest position is kept beside
-- it for the dispatcher and the assigned responder.

alter table public.incident_report
  add column cancel_requested_at timestamptz,
  add column cancel_reason text check (cancel_reason in ('safeNow', 'mistake', 'other')),
  add column cancel_note text check (length(cancel_note) <= 200),
  -- Closed because the resident asked.
  add column cancelled boolean not null default false,
  add column last_latitude double precision check (last_latitude between -90 and 90),
  add column last_longitude double precision check (last_longitude between -180 and 180),
  add column last_accuracy_m double precision,
  add column last_location_at timestamptz;

alter table public.incident_event drop constraint incident_event_kind_check;
alter table public.incident_event add constraint incident_event_kind_check check (kind in (
  'received', 'smsCheckSent', 'smsReplyReceived', 'verified', 'typeConfirmed',
  'assigned', 'enRoute', 'onScene', 'resolved', 'markedFalseReport',
  'cancelRequested', 'cancelWithdrawn'
));

alter table public.audit_log drop constraint audit_log_action_type_check;
alter table public.audit_log add constraint audit_log_action_type_check check (action_type in (
  'verified', 'markedFalseReport', 'typeConfirmed', 'unitAssigned', 'unitReassigned',
  'statusChanged', 'resolved', 'smsCheckSent', 'contactViewed', 'settingChanged',
  'unitAdded', 'unitEdited', 'unitRetired', 'unitRestored', 'rosterChanged',
  'accountCreated', 'accountUpdated', 'accountDeactivated', 'accountReactivated',
  'passwordReset', 'residentSuspended', 'residentRestored', 'weatherSimulated',
  'alertIssued', 'alertEnded', 'reportDrafted', 'reportFinalized',
  'sosSimulated', 'reportsSimulated', 'sosCancelled'
));

-- ------------------------------------------------------------ resident

-- The resident's own open SOS, locked. `not_found` for someone else's or
-- an unknown one; `incident_closed` once it is resolved.
create function private.my_open_sos(p_client_uuid uuid)
returns public.incident_report
language plpgsql security definer set search_path = ''
as $$
declare
  me public.manila_resident := private.require_resident();
  inc public.incident_report;
begin
  select * into inc from public.incident_report i
   where i.client_uuid = p_client_uuid and i.manila_resident_id = me.manila_resident_id
   for update;
  if inc.incident_id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if inc.status = 'resolved' then
    raise exception 'incident_closed' using errcode = 'P0001';
  end if;
  return inc;
end $$;

-- R2 "Cancel SOS". Asking twice changes nothing.
create function public.request_sos_cancel(
  p_client_uuid uuid,
  p_reason text,
  p_note text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  inc public.incident_report := private.my_open_sos(p_client_uuid);
  v_note text := nullif(btrim(p_note), '');
begin
  if p_reason is null or p_reason not in ('safeNow', 'mistake', 'other')
     or length(v_note) > 200 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  -- With the unit there, the responder settles it in person.
  if inc.status = 'onScene' then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if inc.cancel_requested_at is not null then
    return;
  end if;
  update public.incident_report
     set cancel_requested_at = now(), cancel_reason = p_reason, cancel_note = v_note
   where incident_id = inc.incident_id;
  insert into public.incident_event (incident_id, kind, detail)
  values (inc.incident_id, 'cancelRequested', p_reason);
end $$;

-- R2 "I still need help".
create function public.withdraw_sos_cancel(p_client_uuid uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  inc public.incident_report := private.my_open_sos(p_client_uuid);
begin
  if inc.cancel_requested_at is null then
    return;
  end if;
  update public.incident_report
     set cancel_requested_at = null, cancel_reason = null, cancel_note = null
   where incident_id = inc.incident_id;
  insert into public.incident_event (incident_id, kind)
  values (inc.incident_id, 'cancelWithdrawn');
end $$;

-- The phone's position while the SOS is open. At most one every 20
-- seconds is kept; a point outside Manila or a time in the future is
-- refused. Returns whether it was kept.
create function public.update_sos_location(
  p_client_uuid uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_m double precision default null,
  p_captured_at timestamptz default now()
)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  inc public.incident_report := private.my_open_sos(p_client_uuid);
begin
  if p_latitude is null or p_longitude is null or p_captured_at is null
     or p_captured_at > now() + interval '5 minutes'
     or p_accuracy_m < 0 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if not private.inside_manila(p_latitude, p_longitude) then
    raise exception 'outside_manila' using errcode = 'P0001';
  end if;
  if inc.last_location_at is not null
     and (p_captured_at <= inc.last_location_at
          or inc.last_location_at > now() - interval '20 seconds') then
    return false;
  end if;
  update public.incident_report
     set last_latitude = p_latitude, last_longitude = p_longitude,
         last_accuracy_m = p_accuracy_m, last_location_at = p_captured_at
   where incident_id = inc.incident_id;
  return true;
end $$;

-- ------------------------------------------------------------ dispatcher

-- D4 "Close as cancelled": only after the resident asked.
create function public.confirm_sos_cancel(p_incident_id text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  inc public.incident_report := public._open_incident(p_incident_id);
begin
  if inc.cancel_requested_at is null then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  perform public._release_unit(inc.assigned_unit_id);
  perform public._close_dispatch(inc.incident_id);
  update public.incident_report
     set status = 'resolved', cancelled = true, resolved_at = now()
   where incident_id = inc.incident_id;
  insert into public.incident_event (incident_id, kind, actor_name, detail)
  values (inc.incident_id, 'resolved', me.display_name, 'cancelledByResident');
  insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id, detail)
  values (me.id::text, me.display_name, me.role, 'sosCancelled', 'incident_report', inc.incident_id, inc.cancel_reason);
end $$;

revoke all on function private.my_open_sos(uuid) from public, anon, authenticated;
revoke all on function public.request_sos_cancel(uuid, text, text) from public, anon;
revoke all on function public.withdraw_sos_cancel(uuid) from public, anon;
revoke all on function public.update_sos_location(uuid, double precision, double precision, double precision, timestamptz) from public, anon;
revoke all on function public.confirm_sos_cancel(text) from public, anon;
grant execute on function public.request_sos_cancel(uuid, text, text) to authenticated;
grant execute on function public.withdraw_sos_cancel(uuid) to authenticated;
grant execute on function public.update_sos_location(uuid, double precision, double precision, double precision, timestamptz) to authenticated;
grant execute on function public.confirm_sos_cancel(text) to authenticated;

-- ------------------------------------------------------------ board

-- The board shows the cancel request and the newest position (appended
-- columns).
create or replace view public.incident_board with (security_invoker = true) as
select
  i.incident_id as id,
  i.origin, i.channel, i.status, i.suggested_type, i.emergency_type,
  i.latitude, i.longitude, i.barangay, i.district, i.address, i.accuracy_m,
  i.captured_at, i.received_at, i.manila_resident_id, i.people_count, i.note,
  i.vulnerable, i.account_verified, i.mock_location, i.verification_method,
  i.assigned_unit_id, i.suggestion_overridden, i.override_reason,
  i.false_report, i.resolved_at,
  coalesce(
    (select array_agg(c.report_id order by c.submitted_at)
       from public.crowd_report c where c.incident_id = i.incident_id),
    '{}'
  ) as crowd_report_ids,
  coalesce(
    (select jsonb_agg(jsonb_build_object(
        'kind', e.kind, 'at', e.at, 'actor_name', e.actor_name, 'detail', e.detail
      ) order by e.at, e.event_id)
       from public.incident_event e where e.incident_id = i.incident_id),
    '[]'::jsonb
  ) as events,
  p.score as priority_score,
  p.severity as priority_severity,
  p.factors as priority_factors,
  i.is_simulated,
  i.cancel_requested_at, i.cancel_reason, i.cancel_note, i.cancelled,
  i.last_latitude, i.last_longitude, i.last_accuracy_m, i.last_location_at
from public.incident_report i
cross join lateral private.priority_breakdown(i.origin, i.vulnerable, i.captured_at, i.mock_location) p;

-- ------------------------------------------------------------ the apps

-- R2: the resident's SOS requests now say whether a cancel was asked for
-- and whether the SOS was closed as cancelled.
create or replace function public.my_sos()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(x.row order by x.captured_at desc), '[]'::jsonb)
  from (
    select i.captured_at, jsonb_build_object(
      'client_id', coalesce(i.client_uuid::text, i.incident_id),
      'captured_at', i.captured_at,
      'delivery', 'delivered',
      'latitude', i.latitude,
      'longitude', i.longitude,
      'accuracy_m', i.accuracy_m,
      'barangay', i.barangay,
      'district', i.district,
      'details', jsonb_build_object(
        'type', i.suggested_type,
        'people_count', i.people_count,
        'needs_extra_help', i.needs_extra_help,
        'note', i.note),
      'sent_via', i.channel,
      'sent_at', i.received_at,
      'delivered_at', i.received_at,
      'incident_id', i.incident_id,
      'status', i.status,
      'status_times', coalesce((
        select jsonb_object_agg(s.status, s.at)
          from (
            select case e.kind
                     when 'received' then 'pendingVerification'
                     when 'verified' then 'confirmed'
                     when 'assigned' then 'assigned'
                     when 'enRoute' then 'enRoute'
                     when 'onScene' then 'onScene'
                     when 'resolved' then 'resolved'
                     when 'markedFalseReport' then 'resolved'
                   end as status,
                   max(e.at) as at
              from public.incident_event e
             where e.incident_id = i.incident_id
             group by 1
          ) s
         where s.status is not null), '{}'::jsonb),
      'unit_call_sign', u.call_sign,
      'unit_type', u.unit_type,
      'responder_latitude', case when i.status in ('assigned', 'enRoute', 'onScene') then u.last_latitude end,
      'responder_longitude', case when i.status in ('assigned', 'enRoute', 'onScene') then u.last_longitude end,
      'responder_location_at', case when i.status in ('assigned', 'enRoute', 'onScene') then u.last_location_at end,
      'cancel_requested_at', i.cancel_requested_at,
      'cancel_reason', i.cancel_reason,
      'cancelled', i.cancelled
    ) as row
    from public.incident_report i
    left join public.response_unit u on u.unit_id = i.assigned_unit_id
    where i.origin = 'sos'
      and i.manila_resident_id = (select private.current_resident_id())
  ) x
$$;

-- F3, F4: the responder sees the resident's newest position and whether
-- the resident asked to cancel (dispatch decides; the job stays theirs
-- until it is closed).
create or replace function public.my_assignments()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'incident_id', i.incident_id,
      'offered_at', coalesce(
        (select max(e.at) from public.incident_event e
          where e.incident_id = i.incident_id and e.kind = 'assigned'),
        i.received_at),
      'latitude', i.latitude,
      'longitude', i.longitude,
      'barangay', i.barangay,
      'district', i.district,
      'address', i.address,
      'channel', i.channel,
      'type', coalesce(i.emergency_type, i.suggested_type),
      'people_count', i.people_count,
      'resident_note', i.note,
      'vulnerable', to_jsonb(i.vulnerable),
      'status', i.status,
      'accepted_at', (select max(e.at) from public.incident_event e
                       where e.incident_id = i.incident_id and e.kind = 'enRoute'),
      'on_scene_at', (select max(e.at) from public.incident_event e
                       where e.incident_id = i.incident_id and e.kind = 'onScene'),
      'real_emergency', i.real_emergency,
      'not_real_reason', i.not_real_reason,
      'people_found', i.people_found,
      'route', (select jsonb_build_object('polyline', d.route) || coalesce(d.route_plan, '{}'::jsonb)
                  from public.dispatch d
                 where d.incident_id = i.incident_id and d.unit_id = i.assigned_unit_id
                   and d.completion_time is null and d.route is not null
                 order by d.dispatch_time desc limit 1),
      'resident_latitude', i.last_latitude,
      'resident_longitude', i.last_longitude,
      'resident_location_at', i.last_location_at,
      'cancel_requested_at', i.cancel_requested_at
    ) order by i.received_at), '[]'::jsonb)
  from public.incident_report i
  where (select private.current_staff_role()) = 'responder'
    and i.assigned_unit_id = (select private.current_staff_unit())
    and i.status in ('assigned', 'enRoute', 'onScene')
$$;
