-- Routing (plan 10.2, FR3): the route chosen at dispatch, and the Dijkstra
-- timing log for Chapter 4.
--
-- The dashboard ranks units by road travel time (Dijkstra over the bundled
-- OpenStreetMap road graph) and, on Assign, sends the chosen unit's route.
-- The dispatch record keeps it: `route` holds the encoded polyline (the
-- DISPATCH route attribute, Figure 3.6) and `route_plan` the travel time,
-- length, street steps, and how long Dijkstra took. The responder's phone
-- reads it through my_assignments().
--
-- Every Dijkstra run is timed (T_end minus T_start) and logged in
-- routing_run, so Chapter 4 can report execution times. Admins read it.

-- ------------------------------------------------------------ dispatch route

alter table public.dispatch add column route_plan jsonb;
comment on column public.dispatch.route is
  'Encoded polyline (precision 1e-5) of the unit''s road route at dispatch time.';
comment on column public.dispatch.route_plan is
  'Route details from the dashboard: seconds, meters, steps, compute_ms, graph_built.';

-- A route must have the shape the app sends, and stay small.
create or replace function private.valid_route(p jsonb)
returns boolean
language sql immutable set search_path = ''
as $$
  select p is null or (
    jsonb_typeof(p) = 'object'
    and jsonb_typeof(p -> 'polyline') = 'string'
    and jsonb_typeof(p -> 'seconds') = 'number'
    and jsonb_typeof(p -> 'meters') = 'number'
    and (p -> 'steps' is null or jsonb_typeof(p -> 'steps') = 'array')
    and length(p::text) <= 65536
  )
$$;

-- assign_unit gains the route (a new optional last argument). Calls without
-- it work as before.
drop function public.assign_unit(text, text, text);

create function public.assign_unit(
  p_incident_id text,
  p_unit_id text,
  p_override_reason text default null,
  p_route jsonb default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  inc public.incident_report := public._open_incident(p_incident_id);
  u public.response_unit;
begin
  if not private.valid_route(p_route) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
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
  insert into public.dispatch (
    incident_id, unit_id, assigned_by, suggestion_overridden, override_reason, route, route_plan
  )
  values (
    inc.incident_id, u.unit_id, me.id, p_override_reason is not null, p_override_reason,
    p_route ->> 'polyline', p_route - 'polyline'
  );
  insert into public.incident_event (incident_id, kind, actor_name, detail)
  values (inc.incident_id, 'assigned', me.display_name, u.call_sign);
end $$;

revoke execute on function public.assign_unit(text, text, text, jsonb) from public, anon;
grant execute on function public.assign_unit(text, text, text, jsonb) to authenticated;

-- The responder's jobs now carry the route from the open dispatch.
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
                 order by d.dispatch_time desc limit 1)
    ) order by i.received_at), '[]'::jsonb)
  from public.incident_report i
  where (select private.current_staff_role()) = 'responder'
    and i.assigned_unit_id = (select private.current_staff_unit())
    and i.status in ('assigned', 'enRoute', 'onScene')
$$;

-- ------------------------------------------------------------ timing log

create table public.routing_run (
  run_id bigint generated always as identity primary key,
  ran_at timestamptz not null default now(),
  account_id uuid,
  platform text not null check (platform in ('web', 'android', 'other')),
  kind text not null check (kind in ('suggestions', 'route')),
  incident_id text,
  compute_ms numeric(10, 3) not null check (compute_ms >= 0 and compute_ms < 600000),
  candidates int check (candidates between 0 and 10000),
  node_count int check (node_count >= 0),
  edge_count int check (edge_count >= 0),
  graph_built date
);
comment on table public.routing_run is
  'Dijkstra execution times (T_end minus T_start) for Chapter 4. Admins read it.';
create index routing_run_ran_idx on public.routing_run (ran_at desc);

alter table public.routing_run enable row level security;
create policy "routing runs: admins" on public.routing_run
  for select to authenticated using ((select private.is_admin()));
grant select on public.routing_run to authenticated;

-- Staff apps log each run. More than 120 a minute from one account are
-- dropped quietly (a timing log must never block dispatch).
create or replace function public.log_routing_run(
  p_kind text,
  p_platform text,
  p_compute_ms numeric,
  p_incident_id text default null,
  p_candidates int default null,
  p_node_count int default null,
  p_edge_count int default null,
  p_graph_built date default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if private.current_staff_role() is null then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if (select count(*) from public.routing_run r
       where r.account_id = (select auth.uid()) and r.ran_at > now() - interval '1 minute') >= 120 then
    return;
  end if;
  insert into public.routing_run (
    account_id, platform, kind, incident_id, compute_ms, candidates, node_count, edge_count, graph_built
  )
  values (
    (select auth.uid()), p_platform, p_kind, p_incident_id, p_compute_ms, p_candidates,
    p_node_count, p_edge_count, p_graph_built
  );
exception when check_violation or not_null_violation then
  raise exception 'invalid_value' using errcode = 'P0001';
end $$;

revoke execute on function public.log_routing_run(text, text, numeric, text, int, int, int, date) from public, anon;
grant execute on function public.log_routing_run(text, text, numeric, text, int, int, int, date) to authenticated;
revoke execute on function private.valid_route(jsonb) from public, anon, authenticated;
