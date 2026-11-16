-- The crew's report asks what MDRRMD's own forms ask (Joshua, 2026-11-17:
-- "the report is being made or submitted by the responder ... inside here
-- is the same choices they fill up for reporting that incident"; the
-- forms: EMR, Flood Monitoring/Roving, Fire Incident 2026).
--
-- 1. completion_report.details (jsonb): the answers for the incident's
--    type, as the phone sends them (CompletionDetails in packages/shared):
--    medical (type of EMR, cause of a road accident, vehicles, patients
--    with an optional name, age bracket, gender, receiving hospital),
--    flood (cause, cyclone name, wind signal, level, status), fire (type,
--    highest alarm, estimated damage, affected individuals).
--    Patient names are optional (Joshua: "make it optional"); they are
--    removed when the incident is anonymized by the retention job.
-- 2. Photos on the crew's report ('completion'): the responder's own
--    folder in incident-photos, up to 15 per report, tied to the report and
--    its incident, so the board shows them with the incident's photos.
-- 3. The board's crew reports carry the details.

-- ------------------------------------------------------------------ 1. details

alter table public.completion_report add column details jsonb not null default '{}'::jsonb;
comment on column public.completion_report.details is
  'Answers for the incident type, as on MDRRMD''s EMR, flood and fire forms (CompletionDetails). Patient names optional; removed on anonymization.';

-- Shape only: an object, not huge, at most 30 patients with names of at
-- most 100 characters. The phone sends only the choices it shows.
create or replace function private.valid_completion_details(p jsonb)
returns boolean
language sql immutable set search_path = ''
as $$
  select p is not null
     and jsonb_typeof(p) = 'object'
     and octet_length(p::text) <= 20000
     and (not p ? 'patients'
          or (jsonb_typeof(p -> 'patients') = 'array'
              and jsonb_array_length(p -> 'patients') <= 30
              and not exists (
                select 1 from jsonb_array_elements(p -> 'patients') e
                 where jsonb_typeof(e) <> 'object'
                    or length(coalesce(e ->> 'name', '')) > 100)))
$$;
revoke execute on function private.valid_completion_details(jsonb) from public, anon;

alter table public.completion_report
  add constraint completion_report_details_valid check (private.valid_completion_details(details));

drop function public.submit_completion_report(uuid, text, timestamptz, text, int, int, int, int, int, int, text);

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
  p_details jsonb default null
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
    time_on_scene_s, houses_damaged, injured, missing, affected_families, notes, details
  ) values (
    p_report_id, inc.incident_id, me.unit_id, me.id, t, p_outcome, p_persons_assisted,
    coalesce(p_time_on_scene_s, 0), coalesce(p_houses_damaged, 0), coalesce(p_injured, 0),
    coalesce(p_missing, 0), coalesce(p_affected_families, 0), nullif(btrim(p_notes), ''),
    v_details
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
  public.submit_completion_report(uuid, text, timestamptz, text, int, int, int, int, int, int, text, jsonb)
  from public, anon;
grant execute on function
  public.submit_completion_report(uuid, text, timestamptz, text, int, int, int, int, int, int, text, jsonb)
  to authenticated;

-- RA 10173: an anonymized incident keeps its crew figures but loses the
-- patients' names.
create or replace function private.forget_patient_names()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  update public.completion_report c
     set details = jsonb_set(
           c.details, '{patients}',
           coalesce((select jsonb_agg(e - 'name') from jsonb_array_elements(c.details -> 'patients') e),
                    '[]'::jsonb))
   where c.incident_id = new.incident_id
     and jsonb_typeof(c.details -> 'patients') = 'array';
  return new;
end $$;
revoke execute on function private.forget_patient_names() from public, anon, authenticated;

create trigger incident_report_forget_patient_names
  after update of anonymized_at on public.incident_report
  for each row when (old.anonymized_at is null and new.anonymized_at is not null)
  execute function private.forget_patient_names();

-- ------------------------------------------------------------------ 2. photos

alter table public.incident_photo
  add column completion_id uuid references public.completion_report (report_id) on delete cascade;
create index incident_photo_completion_idx on public.incident_photo (completion_id);

alter table public.incident_photo drop constraint incident_photo_kind_check;
alter table public.incident_photo drop constraint incident_photo_check;
alter table public.incident_photo
  add constraint incident_photo_kind_check check (kind in ('sos', 'report', 'completion')),
  add constraint incident_photo_check check ((kind in ('sos', 'completion')) = (incident_id is not null)),
  add constraint incident_photo_completion_check check ((kind = 'completion') = (completion_id is not null));

-- A responder adds files to their own folder too.
create policy "incident photos: a responder uploads into their own folder" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'incident-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select private.current_staff_unit()) is not null
  );

-- Ties an uploaded file to the caller's own SOS ('sos') or crowd report
-- ('report'), or, for a responder, to a crew report they filed
-- ('completion', by the report's id). Sending it again changes nothing.
-- Refused: a record that is not the caller's or not on the server
-- (not_found), a closed SOS (incident_closed), a fourth SOS or report
-- photo or a sixteenth crew report photo (invalid_value).
create or replace function public.attach_photo(p_photo_id uuid, p_kind text, p_client_uuid uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  me public.manila_resident;
  path text;
  sos public.incident_report;
  rep public.crowd_report;
  crew public.completion_report;
begin
  if p_photo_id is null or p_client_uuid is null or p_kind is null
     or p_kind not in ('sos', 'report', 'completion') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if p_kind <> 'completion' then
    me := private.require_resident();
  end if;
  path := (select auth.uid())::text || '/' || p_photo_id::text || '.jpg';
  if exists (select 1 from public.incident_photo p where p.photo_id = p_photo_id) then
    if exists (select 1 from public.incident_photo p
                where p.photo_id = p_photo_id and p.storage_path = path) then
      return p_photo_id;
    end if;
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if not exists (select 1 from storage.objects o
                  where o.bucket_id = 'incident-photos' and o.name = path) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;

  if p_kind = 'completion' then
    select * into crew from public.completion_report c
     where c.report_id = p_client_uuid and c.filed_by = (select auth.uid());
    if crew.report_id is null then
      raise exception 'not_found' using errcode = 'P0001';
    end if;
    if (select count(*) from public.incident_photo p
         where p.completion_id = crew.report_id and p.expired_at is null) >= 15 then
      raise exception 'invalid_value' using errcode = 'P0001';
    end if;
    insert into public.incident_photo (photo_id, kind, client_uuid, incident_id, completion_id, storage_path, uploaded_by)
    values (p_photo_id, 'completion', p_client_uuid, crew.incident_id, crew.report_id, path, (select auth.uid()));
  elsif p_kind = 'sos' then
    select * into sos from public.incident_report i
     where i.client_uuid = p_client_uuid and i.manila_resident_id = me.manila_resident_id;
    if sos.incident_id is null then
      raise exception 'not_found' using errcode = 'P0001';
    end if;
    if sos.status = 'resolved' then
      raise exception 'incident_closed' using errcode = 'P0001';
    end if;
    if (select count(*) from public.incident_photo p
         where p.incident_id = sos.incident_id and p.kind = 'sos' and p.expired_at is null) >= 3 then
      raise exception 'invalid_value' using errcode = 'P0001';
    end if;
    insert into public.incident_photo (photo_id, kind, client_uuid, incident_id, storage_path, uploaded_by)
    values (p_photo_id, 'sos', p_client_uuid, sos.incident_id, path, (select auth.uid()));
  else
    select * into rep from public.crowd_report c
     where c.client_uuid = p_client_uuid and c.manila_resident_id = me.manila_resident_id;
    if rep.report_id is null then
      raise exception 'not_found' using errcode = 'P0001';
    end if;
    if (select count(*) from public.incident_photo p
         where p.report_id = rep.report_id and p.expired_at is null) >= 3 then
      raise exception 'invalid_value' using errcode = 'P0001';
    end if;
    insert into public.incident_photo (photo_id, kind, client_uuid, report_id, storage_path, uploaded_by)
    values (p_photo_id, 'report', p_client_uuid, rep.report_id, path, (select auth.uid()));
  end if;
  return p_photo_id;
end $$;
revoke execute on function public.attach_photo(uuid, text, uuid) from public, anon;
grant execute on function public.attach_photo(uuid, text, uuid) to authenticated;

-- ------------------------------------------------------------------ 3. the board

do $board$
declare
  d text := pg_get_viewdef('public.incident_board'::regclass);
  old_part text := '''corrected'', c.corrected)';
begin
  if position(old_part in d) = 0 then
    raise exception 'incident_board: crew_reports not found';
  end if;
  d := replace(d, old_part, '''corrected'', c.corrected, ''details'', c.details)');
  execute 'create or replace view public.incident_board with (security_invoker = true) as ' || d;
end $board$;
