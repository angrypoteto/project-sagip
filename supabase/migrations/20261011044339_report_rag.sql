-- The RAG step of the NDRRMC report (Objective 4; plan 10.6 and Q26;
-- Joshua chose Google Gemini's free tier on 2026-10-11). Proof of concept.
--
-- A6 can ask the generate-report Edge Function to rewrite a draft. The
-- function finds the reference passages closest to each section
-- (report_reference, by embedding), and has the language model write the
-- section from the report's figures and those passages. The administrator
-- still reviews, edits, and saves it: nothing is saved by the model.
--
-- What leaves the database: the report's figures (counts, barangay names,
-- times) and the assembled draft made from them. No names, numbers,
-- addresses, or coordinates (report_source never had them).
--
-- The passages below are provisional: written from the outline of an
-- NDRRMC situation report until MDRRMD sends the real template and sample
-- reports (thesis Table 3.1 item 5). Replace them with those.

create table public.report_reference (
  reference_id bigint generated always as identity primary key,
  -- The report section it guides (ReportSections), or null for any.
  section_key text,
  title text not null check (length(btrim(title)) between 1 and 160),
  body text not null check (length(btrim(body)) between 1 and 4000),
  -- Where the passage comes from, shown with the draft.
  origin text not null default 'provisional',
  -- The passage's embedding (a JSON array of numbers) and the model that
  -- made it; filled in by generate-report the first time it runs.
  embedding jsonb,
  embedding_model text,
  created_at timestamptz not null default now()
);
comment on table public.report_reference is
  'Reference passages the NDRRMC report is drafted from (RAG). Admins read; generate-report embeds.';
alter table public.report_reference enable row level security;
create policy "report references: admins" on public.report_reference
  for select to authenticated using ((select private.is_admin()));
grant select on public.report_reference to authenticated;

-- One row per rewrite an administrator asked for (how long it took and
-- whether it worked, for Objective 4), and the hourly limit.
create table public.report_rewrite (
  rewrite_id bigint generated always as identity primary key,
  staff_id uuid references public.staff (id) on delete set null,
  asked_at timestamptz not null default now(),
  model text,
  duration_ms int check (duration_ms >= 0),
  ok boolean,
  detail text
);
comment on table public.report_rewrite is
  'Report rewrites asked of the language model (RAG): when, how long, whether it worked. Admins read.';
create index report_rewrite_staff_idx on public.report_rewrite (staff_id, asked_at desc);
alter table public.report_rewrite enable row level security;
create policy "report rewrites: admins" on public.report_rewrite
  for select to authenticated using ((select private.is_admin()));
grant select on public.report_rewrite to authenticated;

-- generate-report calls this with the administrator's own sign-in before
-- anything else: admins only, at most 20 rewrites an hour each. Returns
-- the row to finish.
create function public.begin_report_rewrite()
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  v_id bigint;
begin
  if (select count(*) from public.report_rewrite r
       where r.staff_id = me.id and r.asked_at > now() - interval '1 hour') >= 20 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
  insert into public.report_rewrite (staff_id) values (me.id) returning rewrite_id into v_id;
  return v_id;
end $$;

-- How the rewrite went. Service role only.
create function public.finish_report_rewrite(
  p_rewrite_id bigint,
  p_ok boolean,
  p_model text default null,
  p_duration_ms int default null,
  p_detail text default null
)
returns void
language sql security definer set search_path = ''
as $$
  update public.report_rewrite
     set ok = p_ok, model = left(p_model, 80), duration_ms = p_duration_ms,
         detail = left(p_detail, 300)
   where rewrite_id = p_rewrite_id and ok is null;
$$;

-- Keeps a passage's embedding. Service role only.
create function public.record_reference_embedding(
  p_reference_id bigint,
  p_model text,
  p_embedding jsonb
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if jsonb_typeof(p_embedding) <> 'array' or jsonb_array_length(p_embedding) not between 8 and 4096 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  update public.report_reference
     set embedding = p_embedding, embedding_model = left(p_model, 80)
   where reference_id = p_reference_id;
end $$;

revoke all on function public.begin_report_rewrite() from public, anon;
grant execute on function public.begin_report_rewrite() to authenticated;
revoke all on function public.finish_report_rewrite(bigint, boolean, text, int, text) from public, anon, authenticated;
grant execute on function public.finish_report_rewrite(bigint, boolean, text, int, text) to service_role;
revoke all on function public.record_reference_embedding(bigint, text, jsonb) from public, anon, authenticated;
grant execute on function public.record_reference_embedding(bigint, text, jsonb) to service_role;
grant select on public.report_reference to service_role;

-- A draft whose text the language model rewrote is marked `rag` (the
-- column has been there since ndrrmc_reports). The dashboard calls this
-- right after saving such a draft. Admins only; a final report keeps what
-- it had.
create function public.mark_report_rag(p_report_id text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
begin
  update public.ndrrmc_report
     set method = 'rag'
   where report_id = p_report_id and status = 'draft';
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
end $$;

revoke all on function public.mark_report_rag(text) from public, anon;
grant execute on function public.mark_report_rag(text) to authenticated;

-- ------------------------------------------------------------ passages

insert into public.report_reference (section_key, title, body) values
('overview', 'Situation overview: what it must say',
 'The situation overview opens the report. State the period covered with its start and end date and time, the hazard or weather disturbance behind the incidents (the highest tropical cyclone wind signal, the heaviest rainfall, any storm surge advisory), and the total number of incidents received in the period. Say how many are resolved and how many are still open at the time of reporting. Keep it to one short paragraph. Do not describe individual persons.'),
('overview', 'Situation overview: when there is no weather disturbance',
 'When no tropical cyclone wind signal, rainfall warning, or storm surge advisory was recorded in the period, say so plainly: "No weather disturbance was recorded during the period." Do not guess at a cause. Incidents may still be reported without a weather disturbance, for example fires and medical emergencies.'),
('incidents', 'Incidents reported: structure',
 'List incidents by type (flood, fire, medical, structural), each with its count, largest first. Say how many came as SOS requests from residents and how many were confirmed from clustered crowd reports. Name the barangays with the most incidents and their counts, at most five. Report false reports separately and never count them among the emergencies. If an incident has no confirmed type yet, say how many are unclassified.'),
('incidents', 'Incidents reported: wording of counts',
 'Write every count as a number followed by what is counted, for example "12 flood incidents". Use the same figure everywhere it appears; do not round, estimate, or convert a count into words such as "several" or "about a dozen". When a count is zero, write "none" for that item or leave the item out, but never invent a figure.'),
('population', 'Affected population and casualties',
 'Report the number of families affected, persons assisted or rescued, persons injured, and persons missing, as recorded in the completion reports filed by field rescue personnel. State how many incidents involved households with vulnerable members (senior citizens, persons with disability, pregnant women), as a count only. Never give names, ages, addresses, or contact numbers. If some resolved incidents have no completion report yet, say that the figures are partial and how many reports are still awaited.'),
('population', 'Casualty figures are provisional until validated',
 'Casualty and missing-person figures in a situation report are provisional. Say that they are "as reported by field rescue personnel, subject to validation". A report of zero injured or zero missing is stated as such only when all completion reports for the period have been filed.'),
('damage', 'Damage to houses',
 'Report the number of houses damaged as recorded in completion reports. If the reports do not separate totally damaged from partially damaged houses, give the single total and say it is not broken down. Do not estimate the cost of damage unless a figure was recorded. If no damage was recorded, say "No damage to houses was reported for the period."'),
('response', 'Response actions: what to include',
 'State how many response units were deployed and how many dispatches were made. Give the median time from receipt of an incident to the assignment of a unit, and the median time from receipt to arrival on scene, in minutes and seconds. Summarise the outcomes recorded on scene (rescued, treated, transported, no one found). State how many public alerts or advisories were issued in the period and through which channels if known.'),
('response', 'Response actions: time figures',
 'Give time figures exactly as computed, for example "a median of 4 min 12 s from receipt to dispatch". If a time could not be computed because no unit was assigned or none reached the scene in the period, say that the figure is not available rather than leaving a blank or writing zero.'),
('remarks', 'Remarks and recommendations',
 'Close with remarks that follow from the figures: open incidents that still need action, completion reports still awaited, and areas with repeated incidents that may need pre-positioned units or an advisory. Keep recommendations specific and short. Do not add recommendations the figures do not support. If any figure in the report came from simulated or test data, say so here.'),
(null, 'Style of an NDRRMC situation report',
 'Write in formal, plain English, in the third person and the past tense for events in the period. Use short sentences. Avoid adjectives that judge severity ("devastating", "massive") unless they are part of an official warning name. Use official names: "Tropical Cyclone Wind Signal No. 2", "Heavy Rainfall Warning", "Storm Surge Warning", "Manila City Disaster Risk Reduction and Management Department (MDRRMD)". Write barangays as "Barangay 412, Sampaloc". Use the 24-hour or 12-hour clock consistently with the date, in Philippine Standard Time.'),
(null, 'What a situation report must never contain',
 'A situation report submitted to the NDRRMC through the regional office contains aggregate figures only. It must not contain the names of residents, their contact numbers, home addresses, exact coordinates, or medical details (Data Privacy Act of 2012, RA 10173). It must not contain figures that are not in the records. Where a figure is missing, the report says it is not available.');
