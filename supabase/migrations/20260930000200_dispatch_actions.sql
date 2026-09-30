-- Dispatcher actions, the audit trigger (FR11), and DBSCAN clustering of crowd
-- reports (FR7). The app calls these functions with supabase.rpc(); clients
-- have no direct write access to any table.
--
-- Errors are raised with short codes the app maps to friendly text:
--   not_allowed, incident_closed, unit_not_available, already_assigned,
--   invalid_value, not_found

-- ------------------------------------------------------------ guards

create or replace function public._require_dispatcher()
returns public.staff
language plpgsql stable security definer set search_path = ''
as $$
declare
  me public.staff;
begin
  select * into me from public.staff s where s.id = (select auth.uid());
  if me.id is null or me.role not in ('dispatcher', 'admin') then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  return me;
end $$;

create or replace function public._open_incident(p_incident_id text)
returns public.incident_report
language plpgsql security definer set search_path = ''
as $$
declare
  inc public.incident_report;
begin
  select * into inc from public.incident_report i
   where i.incident_id = p_incident_id
   for update;
  if inc.incident_id is null or inc.status = 'resolved' then
    raise exception 'incident_closed' using errcode = 'P0001';
  end if;
  return inc;
end $$;

create or replace function public._release_unit(p_unit_id text)
returns void
language sql security definer set search_path = ''
as $$
  update public.response_unit
     set status = 'available', current_incident_id = null
   where unit_id = p_unit_id;
$$;

create or replace function public._close_dispatch(p_incident_id text)
returns void
language sql security definer set search_path = ''
as $$
  update public.dispatch
     set completion_time = now()
   where incident_id = p_incident_id and completion_time is null;
$$;

-- ------------------------------------------------------------ actions

create or replace function public.verify_incident(p_incident_id text, p_method text default 'callback')
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  inc public.incident_report := public._open_incident(p_incident_id);
begin
  if p_method not in ('callback', 'smsReply', 'onScene') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  update public.incident_report
     set verification_method = p_method,
         status = case when status = 'pendingVerification' then 'confirmed' else status end
   where incident_id = inc.incident_id;
  insert into public.incident_event (incident_id, kind, actor_name, detail)
  values (inc.incident_id, 'verified', me.display_name, p_method);
end $$;

create or replace function public.send_sms_check(p_incident_id text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  inc public.incident_report := public._open_incident(p_incident_id);
begin
  -- The GSM gateway sends the SMS in Phase 5; for now this records the step.
  insert into public.incident_event (incident_id, kind, actor_name)
  values (inc.incident_id, 'smsCheckSent', me.display_name);
  insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id)
  values (me.id::text, me.display_name, me.role, 'smsCheckSent', 'incident_report', inc.incident_id);
end $$;

create or replace function public.mark_false_report(p_incident_id text, p_reason text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  inc public.incident_report := public._open_incident(p_incident_id);
begin
  perform public._release_unit(inc.assigned_unit_id);
  perform public._close_dispatch(inc.incident_id);
  update public.incident_report
     set status = 'resolved', false_report = true, resolved_at = now()
   where incident_id = inc.incident_id;
  insert into public.incident_event (incident_id, kind, actor_name, detail)
  values (inc.incident_id, 'markedFalseReport', me.display_name, p_reason);
end $$;

create or replace function public.confirm_incident_type(p_incident_id text, p_type text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  inc public.incident_report := public._open_incident(p_incident_id);
begin
  if p_type not in ('flood', 'fire', 'medical', 'structural') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  update public.incident_report set emergency_type = p_type where incident_id = inc.incident_id;
  insert into public.incident_event (incident_id, kind, actor_name, detail)
  values (inc.incident_id, 'typeConfirmed', me.display_name, p_type);
end $$;

create or replace function public.assign_unit(
  p_incident_id text,
  p_unit_id text,
  p_override_reason text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  inc public.incident_report := public._open_incident(p_incident_id);
  u public.response_unit;
begin
  if inc.assigned_unit_id = p_unit_id then
    raise exception 'already_assigned' using errcode = 'P0001';
  end if;
  -- Lock the unit so two dispatchers cannot take it at the same moment.
  select * into u from public.response_unit r where r.unit_id = p_unit_id for update;
  if u.unit_id is null or u.status <> 'available' or u.current_incident_id is not null then
    raise exception 'unit_not_available' using errcode = 'P0001';
  end if;

  if inc.assigned_unit_id is not null then
    perform public._release_unit(inc.assigned_unit_id);
    perform public._close_dispatch(inc.incident_id);
  end if;

  update public.response_unit set current_incident_id = inc.incident_id where unit_id = u.unit_id;
  update public.incident_report
     set status = 'assigned',
         assigned_unit_id = u.unit_id,
         suggestion_overridden = p_override_reason is not null,
         override_reason = p_override_reason
   where incident_id = inc.incident_id;
  insert into public.dispatch (incident_id, unit_id, assigned_by, suggestion_overridden, override_reason)
  values (inc.incident_id, u.unit_id, me.id, p_override_reason is not null, p_override_reason);
  insert into public.incident_event (incident_id, kind, actor_name, detail)
  values (inc.incident_id, 'assigned', me.display_name, u.call_sign);
end $$;

create or replace function public.resolve_incident(p_incident_id text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  inc public.incident_report := public._open_incident(p_incident_id);
begin
  perform public._release_unit(inc.assigned_unit_id);
  perform public._close_dispatch(inc.incident_id);
  update public.incident_report set status = 'resolved', resolved_at = now()
   where incident_id = inc.incident_id;
  insert into public.incident_event (incident_id, kind, actor_name)
  values (inc.incident_id, 'resolved', me.display_name);
end $$;

-- Returns a resident's full number for a callback and logs who looked (NFR4).
create or replace function public.reveal_resident_contact(p_resident_id text)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  num text;
begin
  select r.contact_number into num from public.manila_resident r
   where r.manila_resident_id = p_resident_id;
  if num is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id)
  values (me.id::text, me.display_name, me.role, 'contactViewed', 'manila_resident', p_resident_id);
  return num;
end $$;

-- Internal helpers are not callable from the app.
revoke execute on function
  public._require_dispatcher(), public._open_incident(text),
  public._release_unit(text), public._close_dispatch(text)
from public, anon, authenticated;

-- Actions: signed-in users only (each function checks the role itself).
revoke execute on function
  public.verify_incident(text, text), public.send_sms_check(text),
  public.mark_false_report(text, text), public.confirm_incident_type(text, text),
  public.assign_unit(text, text, text), public.resolve_incident(text),
  public.reveal_resident_contact(text)
from public, anon;
grant execute on function
  public.verify_incident(text, text), public.send_sms_check(text),
  public.mark_false_report(text, text), public.confirm_incident_type(text, text),
  public.assign_unit(text, text, text), public.resolve_incident(text),
  public.reveal_resident_contact(text)
to authenticated;

-- ------------------------------------------------------------ audit trigger

-- Writes an audit entry for every assignment, verification, type decision,
-- and status change on an incident, whoever or whatever made it (FR11).
-- Changes made outside the app (SQL editor, demo functions) are logged as
-- 'System'.
create or replace function public.audit_incident_change()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  actor_id text;
  actor_name text;
  actor_role text;
  unit_call text;
  assigned_changed boolean := new.assigned_unit_id is distinct from old.assigned_unit_id
                              and new.assigned_unit_id is not null;
  verified_changed boolean := new.verification_method is distinct from old.verification_method
                              and new.verification_method is not null;
begin
  select s.id::text, s.display_name, s.role into actor_id, actor_name, actor_role
    from public.staff s where s.id = uid;
  if actor_id is null then
    actor_id := coalesce(uid::text, 'system');
    actor_name := case when uid is null then 'System' else 'Resident' end;
    actor_role := case when uid is null then 'system' else 'resident' end;
  end if;

  if assigned_changed then
    select u.call_sign into unit_call from public.response_unit u where u.unit_id = new.assigned_unit_id;
    insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id, detail)
    values (actor_id, actor_name, actor_role,
            case when old.assigned_unit_id is null then 'unitAssigned' else 'unitReassigned' end,
            'dispatch', new.incident_id,
            unit_call || coalesce(' (override: ' || new.override_reason || ')', ''));
  end if;

  if verified_changed then
    insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id, detail)
    values (actor_id, actor_name, actor_role, 'verified', 'incident_report', new.incident_id, new.verification_method);
  end if;

  if new.emergency_type is distinct from old.emergency_type and new.emergency_type is not null then
    insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id, detail)
    values (actor_id, actor_name, actor_role, 'typeConfirmed', 'incident_report', new.incident_id, new.emergency_type);
  end if;

  if new.false_report and not old.false_report then
    insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id)
    values (actor_id, actor_name, actor_role, 'markedFalseReport', 'incident_report', new.incident_id);
  elsif new.status is distinct from old.status then
    if new.status = 'resolved' then
      insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id)
      values (actor_id, actor_name, actor_role, 'resolved', 'incident_report', new.incident_id);
    elsif not assigned_changed and not verified_changed then
      insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id, detail)
      values (actor_id, actor_name, actor_role, 'statusChanged', 'incident_report', new.incident_id,
              old.status || ' -> ' || new.status);
    end if;
  end if;

  return new;
end $$;

create trigger incident_report_audit
  after update on public.incident_report
  for each row execute function public.audit_incident_change();

revoke execute on function public.audit_incident_change() from public, anon, authenticated;

-- ------------------------------------------------------------ DBSCAN

-- After new crowd reports arrive, clusters the last 60 minutes of reports
-- with DBSCAN (eps 50 m, minPts 3; thesis Chapter 3). Each new cluster
-- becomes a confirmed incident; reports joining an existing cluster are
-- linked to its incident. Distances are measured in UTM zone 51N
-- (EPSG:32651), which covers Manila; at 50 m this matches haversine
-- distance to within centimetres (plan Q25).
create or replace function public.recluster_crowd_reports()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  c record;
  new_id text;
begin
  for c in
    with recent as (
      select r.report_id, r.incident_id, r.category, r.latitude, r.longitude,
             r.barangay, r.district, r.source, r.submitted_at,
             extensions.st_clusterdbscan(
               extensions.st_transform(
                 extensions.st_setsrid(extensions.st_makepoint(r.longitude, r.latitude), 4326),
                 32651
               ),
               50, 3
             ) over () as cluster_id
        from public.crowd_report r
       where r.submitted_at > now() - interval '60 minutes'
    )
    select cluster_id,
           array_agg(report_id order by submitted_at) as report_ids,
           (array_agg(incident_id order by submitted_at) filter (where incident_id is not null))[1] as incident_id,
           mode() within group (order by category) filter (where category is not null) as category,
           avg(latitude) as latitude,
           avg(longitude) as longitude,
           min(submitted_at) as first_at,
           (array_agg(barangay order by submitted_at))[1] as barangay,
           (array_agg(district order by submitted_at))[1] as district,
           (array_agg(source order by submitted_at))[1] as source
      from recent
     where cluster_id is not null
     group by cluster_id
  loop
    if c.incident_id is null then
      insert into public.incident_report (
        origin, channel, status, suggested_type, latitude, longitude,
        barangay, district, captured_at, received_at
      ) values (
        'crowdCluster', c.source, 'confirmed', c.category, c.latitude, c.longitude,
        c.barangay, c.district, c.first_at, now()
      ) returning incident_id into new_id;
      insert into public.incident_event (incident_id, kind) values (new_id, 'received');
      update public.crowd_report set incident_id = new_id where report_id = any (c.report_ids);
    else
      update public.crowd_report set incident_id = c.incident_id
       where report_id = any (c.report_ids) and incident_id is null;
    end if;
  end loop;
  return null;
end $$;

create trigger crowd_report_cluster
  after insert on public.crowd_report
  for each statement execute function public.recluster_crowd_reports();

revoke execute on function public.recluster_crowd_reports() from public, anon, authenticated;
