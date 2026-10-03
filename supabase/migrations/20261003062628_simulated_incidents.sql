-- Simulated incidents for demos and UAT (plan 10.3: "simulated report
-- generator"; thesis scope: DBSCAN runs on simulated input).
--
-- While simulation mode is on (A3), an administrator can make
-- - a simulated SOS in a chosen barangay (simulate_sos), and
-- - simulated crowd reports there (simulate_crowd_reports): three or more
--   within about 20 m, so DBSCAN turns them into a confirmed incident live.
-- They go through the same triggers as real ones (the classifier tags the
-- reports, DBSCAN clusters them) and can be verified, assigned, and
-- resolved like any incident. Each is audited.
--
-- `is_simulated` marks them on incident_report and crowd_report. A cluster
-- is simulated while every report in it is. Simulated incidents are left
-- out of A4 analytics, the Objective 3 delivery report, and NDRRMC report
-- figures, so a demo never counts as a measurement.

alter table public.incident_report add column is_simulated boolean not null default false;
alter table public.crowd_report add column is_simulated boolean not null default false;

alter table public.audit_log drop constraint audit_log_action_type_check;
alter table public.audit_log add constraint audit_log_action_type_check check (action_type in (
  'verified', 'markedFalseReport', 'typeConfirmed', 'unitAssigned', 'unitReassigned',
  'statusChanged', 'resolved', 'smsCheckSent', 'contactViewed', 'settingChanged',
  'unitAdded', 'unitEdited', 'unitRetired', 'unitRestored', 'rosterChanged',
  'accountCreated', 'accountUpdated', 'accountDeactivated', 'accountReactivated',
  'passwordReset', 'residentSuspended', 'residentRestored', 'weatherSimulated',
  'alertIssued', 'alertEnded', 'reportDrafted', 'reportFinalized',
  'sosSimulated', 'reportsSimulated'
));

-- ------------------------------------------------------------ board

-- The board shows which incidents are simulated (appended column).
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
  i.is_simulated
from public.incident_report i
cross join lateral private.priority_breakdown(i.origin, i.vulnerable, i.captured_at, i.mock_location) p;

-- ------------------------------------------------------------ clusters

-- A cluster is simulated while all of its reports are. Runs when DBSCAN
-- links a report to an incident.
create function private.mark_simulated_cluster()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.incident_id is not null and new.incident_id is distinct from old.incident_id then
    update public.incident_report i
       set is_simulated = not exists (
             select 1 from public.crowd_report c
              where c.incident_id = new.incident_id and not c.is_simulated)
     where i.incident_id = new.incident_id and i.origin = 'crowdCluster';
  end if;
  return null;
end $$;

create trigger crowd_report_simulated_cluster
  after update of incident_id on public.crowd_report
  for each row execute function private.mark_simulated_cluster();

revoke execute on function private.mark_simulated_cluster() from public, anon, authenticated;

-- ------------------------------------------------------------ the tools

-- A point near a barangay's centre: up to [p_meters] away in a random
-- direction.
create function private.jitter(p_lat double precision, p_lng double precision, p_meters double precision)
returns table (lat double precision, lng double precision)
language sql volatile set search_path = ''
as $$
  select p_lat + d * cos(a) / 110574.0,
         p_lng + d * sin(a) / (111320.0 * cos(radians(p_lat)))
    from (select random() * p_meters as d, random() * 2 * pi() as a) x
$$;

create function private.require_simulation()
returns public.staff
language plpgsql stable security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
begin
  if not private.setting_flag('demo.simulation') then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  return me;
end $$;

-- A simulated SOS in [p_barangay]: on the board at once as Pending
-- Verification, from an unknown sender (no resident), optionally with a
-- senior citizen in the household. Returns the incident id.
create or replace function public.simulate_sos(p_barangay text, p_vulnerable boolean default false)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_simulation();
  b public.barangay;
  pt record;
  new_id text;
begin
  select * into b from public.barangay x where x.name = p_barangay;
  if b.name is null or b.center_latitude is null then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  select * into pt from private.jitter(b.center_latitude, b.center_longitude, 60);
  insert into public.incident_report (
    origin, channel, status, latitude, longitude, barangay, district, accuracy_m,
    captured_at, received_at, vulnerable, account_verified, mock_location, is_simulated
  ) values (
    'sos', 'app', 'pendingVerification', pt.lat, pt.lng, b.name, b.district, 8,
    now() - interval '2 seconds', now(),
    case when coalesce(p_vulnerable, false) then array['seniorCitizen'] else '{}' end,
    false, false, true
  ) returning incident_id into new_id;
  insert into public.incident_event (incident_id, kind) values (new_id, 'received');
  perform private.audit_admin(me, 'sosSimulated', 'incident_report', new_id, b.name || ', ' || b.district);
  return new_id;
end $$;

-- [p_count] simulated crowd reports (1 to 5) of [p_type] within about 20 m
-- of each other in [p_barangay]. Three or more become a confirmed incident
-- through DBSCAN. Returns the report ids.
create or replace function public.simulate_crowd_reports(
  p_barangay text,
  p_type text,
  p_count int default 3
)
returns text[]
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_simulation();
  b public.barangay;
  centre record;
  pt record;
  texts text[];
  ids text[] := '{}';
  new_id text;
begin
  select * into b from public.barangay x where x.name = p_barangay;
  if b.name is null or b.center_latitude is null
     or p_type is null or p_type not in ('flood', 'fire', 'medical', 'structural')
     or p_count is null or p_count not between 1 and 5 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  texts := case p_type
    when 'flood' then array[
      'Baha na dito sa kalsada, hanggang tuhod na ang tubig',
      'Flooded street, the water is rising fast',
      'Lubog na yung daan, may mga bata dito',
      'Baha sa kanto, hindi na madaanan ng sasakyan',
      'Flood water entering the houses here']
    when 'fire' then array[
      'May sunog sa kabilang bahay, makapal ang usok',
      'Fire spreading to the nearby houses',
      'Nasusunog ang bodega sa kanto',
      'Malaking apoy, may naiipit na tao',
      'Smoke and fire from the second floor']
    when 'medical' then array[
      'May nahimatay dito, kailangan ng ambulansya',
      'An injured man needs help, he is bleeding',
      'Hindi makahinga ang matanda',
      'Nabangga ng motor, sugatan',
      'A woman collapsed on the sidewalk']
    else array[
      'Gumuho ang pader ng bahay',
      'A wall collapsed, people may be trapped',
      'Bumagsak ang bubong ng tindahan',
      'May bitak ang gusali, delikado',
      'Part of the building fell on the street']
  end;
  select * into centre from private.jitter(b.center_latitude, b.center_longitude, 60);
  for i in 1 .. p_count loop
    select * into pt from private.jitter(centre.lat, centre.lng, 20);
    insert into public.crowd_report (
      description, latitude, longitude, barangay, district, source,
      captured_at, accuracy_m, reported_type, is_simulated
    ) values (
      texts[i], pt.lat, pt.lng, b.name, b.district, 'app',
      now(), 10, p_type, true
    ) returning report_id into new_id;
    ids := ids || new_id;
  end loop;
  perform private.audit_admin(me, 'reportsSimulated', 'crowd_report', ids[1],
    p_count || ' ' || p_type || ' reports in ' || b.name || ', ' || b.district);
  return ids;
end $$;

revoke execute on function
  private.jitter(double precision, double precision, double precision),
  private.require_simulation()
from public, anon, authenticated;
revoke execute on function public.simulate_sos(text, boolean) from public, anon;
grant execute on function public.simulate_sos(text, boolean) to authenticated;
revoke execute on function public.simulate_crowd_reports(text, text, int) from public, anon;
grant execute on function public.simulate_crowd_reports(text, text, int) to authenticated;

-- ------------------------------------------------------------ measurements

-- A4, A5/A6, and the Objective 3 report leave simulated incidents out.
do $$
declare
  fn text;
  def text;
begin
  foreach fn in array array[
    'public.analytics_report(timestamptz, timestamptz)',
    'public.report_source(timestamptz, timestamptz)',
    'public.sos_delivery_report(timestamptz, timestamptz)'
  ] loop
    select pg_get_functiondef(fn::regprocedure) into def;
    if position('and not i.is_simulated' in def) > 0 then
      continue;
    end if;
    def := regexp_replace(def,
      '(i\.received_at < p_to)',
      '\1 and not i.is_simulated');
    if position('and not i.is_simulated' in def) = 0 then
      raise exception '% was not updated', fn;
    end if;
    execute def;
  end loop;
end $$;
