-- RAG on the responder's report (Joshua, 2026-11-17: "can we make the
-- responder report have the rag so it will be the rag part"; and the
-- narrative too: "can you do both?"). Objective 4.
--
-- The responder writes or dictates what happened; the edge function
-- fill-crew-report retrieves MDRRMD's form guidance for the incident's type
-- (report_reference, section_key 'crew_<type>') and validated past crew
-- reports of the same type (crew_report_examples), and the language model
-- fills in the form's answers and writes a short narrative. The responder
-- checks them before submitting; nothing is saved by the function.
--
-- 1. crew_report_fill: one row per run (who, which incident, how long,
--    which model, how the passages were found), for the Objective 4
--    timings. begin_crew_report_fill() checks the caller is a responder
--    whose unit holds the open incident, limits runs to 30 an hour, and
--    gives the function the incident's type and the SOS sender's name (only
--    so it can be removed from the notes before they leave the server).
-- 2. crew_report_examples(): validated crew reports of a type, newest
--    first, without patients' names. Service role only.
-- 3. The form guidance passages (from MDRRMD's EMR, flood and fire forms).
-- 4. completion_report.narrative and filled_by_rag; the board shows both.

-- ------------------------------------------------------------------ 1. runs

create table public.crew_report_fill (
  fill_id bigint generated always as identity primary key,
  staff_id uuid not null references public.staff (id) on delete cascade,
  incident_id text not null references public.incident_report (incident_id) on delete cascade,
  incident_type text,
  asked_at timestamptz not null default now(),
  finished_at timestamptz,
  ok boolean,
  model text,
  duration_ms int,
  retrieval text,
  detail text
);
comment on table public.crew_report_fill is
  'Each "Fill from notes" run on a crew report (RAG, Objective 4): timing and model. No notes are kept.';
create index crew_report_fill_staff_idx on public.crew_report_fill (staff_id, asked_at);

alter table public.crew_report_fill enable row level security;
create policy "crew report fills: admins read" on public.crew_report_fill
  for select to authenticated using ((select private.is_admin()));
grant select on public.crew_report_fill to authenticated;

create function public.begin_crew_report_fill(p_incident_id text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_responder();
  inc public.incident_report;
  v_id bigint;
  v_type text;
  v_name text;
begin
  select * into inc from public.incident_report i where i.incident_id = p_incident_id;
  if inc.incident_id is null or inc.assigned_unit_id is distinct from me.unit_id
     or inc.status not in ('assigned', 'enRoute', 'onScene') then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if (select count(*) from public.crew_report_fill f
       where f.staff_id = me.id and f.asked_at > now() - interval '1 hour') >= 30 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
  v_type := coalesce(inc.emergency_type, inc.suggested_type);
  select nullif(btrim(r.fullname), '') into v_name
    from public.manila_resident r
   where inc.origin = 'sos' and inc.anonymized_at is null
     and r.manila_resident_id = inc.manila_resident_id;
  insert into public.crew_report_fill (staff_id, incident_id, incident_type)
  values (me.id, inc.incident_id, v_type) returning fill_id into v_id;
  return jsonb_build_object('fill_id', v_id, 'type', v_type, 'names',
    case when v_name is null then '[]'::jsonb else jsonb_build_array(v_name) end);
end $$;
revoke execute on function public.begin_crew_report_fill(text) from public, anon;
grant execute on function public.begin_crew_report_fill(text) to authenticated;

create function public.finish_crew_report_fill(
  p_fill_id bigint, p_ok boolean, p_model text, p_duration_ms int, p_retrieval text, p_detail text
)
returns void
language sql security definer set search_path = ''
as $$
  update public.crew_report_fill
     set finished_at = now(), ok = p_ok, model = left(p_model, 100),
         duration_ms = greatest(p_duration_ms, 0), retrieval = left(p_retrieval, 40),
         detail = left(p_detail, 300)
   where fill_id = p_fill_id and finished_at is null
$$;
revoke execute on function public.finish_crew_report_fill(bigint, boolean, text, int, text, text)
  from public, anon, authenticated;
grant execute on function public.finish_crew_report_fill(bigint, boolean, text, int, text, text)
  to service_role;

-- ------------------------------------------------------------------ 2. examples

-- The narrative column first: the examples read it (section 4).
alter table public.completion_report
  add column narrative text check (length(narrative) <= 2000),
  add column filled_by_rag boolean not null default false;
comment on column public.completion_report.narrative is
  'Short account of the incident for MDRRMD, written by the language model from the responder''s notes (RAG) and checked by the responder.';


create function public.crew_report_examples(p_type text, p_limit int default 3)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(x.ex), '[]'::jsonb) from (
    select jsonb_build_object(
             'details', c.details || case
               when jsonb_typeof(c.details -> 'patients') = 'array' then jsonb_build_object('patients',
                 (select coalesce(jsonb_agg(e - 'name'), '[]'::jsonb)
                    from jsonb_array_elements(c.details -> 'patients') e))
               else '{}'::jsonb end,
             'injured', c.injured, 'persons_assisted', c.persons_assisted,
             'affected_families', c.affected_families, 'houses_damaged', c.houses_damaged,
             'narrative', c.narrative) as ex
      from public.completion_report c
      join public.incident_report i on i.incident_id = c.incident_id
     where c.validated_at is not null
       and c.details <> '{}'::jsonb
       and coalesce(i.emergency_type, i.suggested_type) = p_type
       and i.anonymized_at is null
     order by c.validated_at desc
     limit least(greatest(coalesce(p_limit, 3), 0), 5)
  ) x
$$;
revoke execute on function public.crew_report_examples(text, int) from public, anon, authenticated;
grant execute on function public.crew_report_examples(text, int) to service_role;

-- ------------------------------------------------------------------ 3. guidance

insert into public.report_reference (section_key, title, body, origin) values
('crew_medical', 'MDRRMD Emergency Medical Response Form: type of EMR',
 'TYPE OF EMR is one of: Vehicular / Road Accident (a crash, a vehicle hitting a person or another vehicle), Medical Call (a person sick or injured at home or in a public place, not from a road crash), Medical Standby (an ambulance and crew posted at an event or operation), Patient Transport (moving a patient between home and hospital or between hospitals).',
 'MDRRMD Emergency Medical Response Form (2026)'),
('crew_medical', 'MDRRMD Emergency Medical Response Form: road accidents',
 'For a road accident the form asks the CAUSE OF ROAD ACCIDENT (Drunk Driving, Loss of Control, Brake Failure, Overspeeding, Driver Negligence, Road Condition, Road Hazards, Inclement Weather, Road Traffic Collision, Other) and the TYPE OF VEHICLE INVOLVED for each vehicle (Pedestrian, Bicycle, Motorcycle, E-bike, Tricycle, E-trike, Sedan, SUV, Van, Taxi, PUJ, PUV, Truck, Ambulance, Fire Truck, Other). A pedestrian hit by a vehicle is listed as a vehicle involved.',
 'MDRRMD Emergency Medical Response Form (2026)'),
('crew_medical', 'MDRRMD Emergency Medical Response Form: patients',
 'For each patient the form asks the AGE bracket (0-17, 18-25, 26-30, 31-35, 36-40, 41-45, 46-50, 51-60, 61 and above), GENDER (Male, Female, Other), RECEIVING HOSPITAL (Refused to transport, Double two upon arrival, Philippine Orthopedic Center, Ospital ng Maynila (OSMA), Ospital ng Sampaloc (OSAM), Ospital ng Tondo, Philippine General Hospital (PGH), Sta. Ana Hospital, Gat Andres Bonifacio Hospital, Tondo Medical Hospital, Jose Reyes Hospital, Chinese General Hospital, Metropolitan Hospital, Manila Medical Center, St. Jude Hospital, Infant Jesus Hospital, UST Hospital, Manila Doctor''s Hospital, Mary Johnston Hospital, JJASGEN, UERM, Other), the CHIEF COMPLAINT and REMARKS. "Lolo" or "lola" means an elderly man or woman.',
 'MDRRMD Emergency Medical Response Form (2026)'),
('crew_flood', 'MDRRMD Flood Monitoring Form: cause and wind signal',
 'CAUSE OF FLOOD is one of: Clogged Waterways, Heavy Rainfall, Tropical Cyclone, Storm Surge. For a tropical cyclone the form asks its name and the Tropical Cyclone Wind Signal: Signal 1 winds of 39-61 km/h within 36 hours; Signal 2 62-88 km/h within 24 hours; Signal 3 89-117 km/h within 18 hours; Signal 4 118-184 km/h within 12 hours; Signal 5 185 km/h or more within 12 hours.',
 'MDRRMD Flood Monitoring/Roving Form (2026)'),
('crew_flood', 'MDRRMD Flood Monitoring Form: flood level and status',
 'FLOOD LEVEL: Gutter deep (8 inches), Half-knee deep (10 inches), Half-tire deep (13 inches), Knee deep (19 inches), Tire deep (28 inches), Waist deep (37 inches), Chest deep (45 inches), Above the chest, Head deep. FLOOD STATUS: Passable to all types of vehicles (PATV) for gutter to half-knee deep; Not passable to light vehicles (NPLV) for half-tire to knee deep; Not passable to all types of vehicles (NPATV) for waist and chest deep.',
 'MDRRMD Flood Monitoring/Roving Form (2026)'),
('crew_fire', 'MDRRMD Fire Incident Form',
 'TYPE OF FIRE INCIDENT is one of: Rubbish, Electrical, Commercial, Residential, Government Office, Vehicular Fire, Warehouse, Residential/Commercial. HIGHEST ALARM LEVEL: 1st to 5th alarm, Task Force Alpha to Echo, General Alarm. The form also asks the estimated damage in pesos, the number of injured, affected families and affected individuals, and the alarm details (1st alarm, 2nd alarm, fire under control, fire out times).',
 'MDRRMD Fire Incident Report Form (2026)');

-- ------------------------------------------------------------------ 4. narrative


drop function public.submit_completion_report(uuid, text, timestamptz, text, int, int, int, int, int, int, text, jsonb);

-- F6: the completion and damage report. The crew's job ends; the incident
-- waits for MDRRMD (validate_crew_report). Sending the same report id
-- again does nothing.
create function public.submit_completion_report(
  p_report_id uuid,
  p_incident_id text,
  p_captured_at timestamptz,
  p_outcome text,
  p_persons_assisted int,
  p_time_on_scene_s int default 0,
  p_houses_damaged int default 0,
  p_injured int default 0,
  p_missing int default 0,
  p_affected_families int default 0,
  p_notes text default null,
  p_details jsonb default null,
  p_narrative text default null,
  p_filled_by_rag boolean default false
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_responder();
  inc public.incident_report;
  t timestamptz := private.capture_time(p_captured_at);
  v_details jsonb := coalesce(p_details, '{}'::jsonb);
begin
  if p_report_id is null
     or p_outcome not in ('rescued', 'treated', 'transported', 'noOneFound', 'falseReport')
     or least(p_persons_assisted, p_time_on_scene_s, p_houses_damaged, p_injured,
              p_missing, p_affected_families) < 0
     or p_persons_assisted is null
     or length(p_notes) > 1000
     or length(p_narrative) > 2000
     or not private.valid_completion_details(v_details) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.completion_report c where c.report_id = p_report_id) then
    return;
  end if;
  select * into inc from public.incident_report i where i.incident_id = p_incident_id for update;
  if inc.incident_id is null or inc.assigned_unit_id is distinct from me.unit_id then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;

  insert into public.completion_report (
    report_id, incident_id, unit_id, filed_by, captured_at, outcome, persons_assisted,
    time_on_scene_s, houses_damaged, injured, missing, affected_families, notes, details,
    narrative, filled_by_rag
  ) values (
    p_report_id, inc.incident_id, me.unit_id, me.id, t, p_outcome, p_persons_assisted,
    coalesce(p_time_on_scene_s, 0), coalesce(p_houses_damaged, 0), coalesce(p_injured, 0),
    coalesce(p_missing, 0), coalesce(p_affected_families, 0), nullif(btrim(p_notes), ''),
    v_details, nullif(btrim(p_narrative), ''), coalesce(p_filled_by_rag, false)
  ) on conflict (incident_id, unit_id) do nothing;

  if inc.status <> 'resolved' and inc.done_reported_at is null then
    update public.incident_report set done_reported_at = t
     where incident_id = inc.incident_id;
    insert into public.incident_event (incident_id, kind, at, actor_name, detail)
    values (inc.incident_id, 'doneReported', t, private.call_sign(me.unit_id), p_outcome);
  end if;
  update public.dispatch set completion_time = t
   where incident_id = inc.incident_id and unit_id = me.unit_id and completion_time is null;
  perform private.release_unit_from(me.unit_id, inc.incident_id);
end $$;
revoke execute on function
  public.submit_completion_report(uuid, text, timestamptz, text, int, int, int, int, int, int, text, jsonb, text, boolean)
  from public, anon;
grant execute on function
  public.submit_completion_report(uuid, text, timestamptz, text, int, int, int, int, int, int, text, jsonb, text, boolean)
  to authenticated;

-- The board's crew reports carry the narrative and whether RAG filled it.
do $board$
declare
  d text := pg_get_viewdef('public.incident_board'::regclass);
  old_part text := '''details'', c.details)';
begin
  if position(old_part in d) = 0 then
    raise exception 'incident_board: crew report details not found';
  end if;
  d := replace(d, old_part,
    '''details'', c.details, ''narrative'', c.narrative, ''filled_by_rag'', c.filled_by_rag)');
  execute 'create or replace view public.incident_board with (security_invoker = true) as ' || d;
end $board$;
