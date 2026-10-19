-- Photos on an SOS or a hazard report (Joshua, 2026-10-19: "optional image
-- upload when sending an SOS; make sure the SOS still sends before the
-- image; also on reporting a hazard, so verification is easier").
--
-- The record always goes first: the phone sends a photo only after its
-- SOS or report, from the outbox, and never by SMS or Bluetooth. A photo
-- is a JPEG of at most 2 MB (the phone shrinks it to about 1280 px and
-- drops its location data) in the private bucket `incident-photos`, at
-- `<uploader's account id>/<photo id>.jpg`; attach_photo() then ties it to
-- the uploader's own SOS or report. At most three per record.
--
-- Who sees a photo: dispatchers and admins; the resident who took it; the
-- responders of the unit assigned to its incident (an SOS's, or the
-- cluster a report belongs to). Nobody changes or removes one from an app.
-- RA 10173: when the incident or report is anonymized by the retention job
-- (data_retention), its photos are hidden from everyone (expired_at). The
-- files themselves can only be removed through the Storage API; that clean
-- up is a follow-up (docs/FEATURE-CHECKLIST.md).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('incident-photos', 'incident-photos', false, 2097152, array['image/jpeg'])
on conflict (id) do nothing;

create table public.incident_photo (
  photo_id uuid primary key,
  kind text not null check (kind in ('sos', 'report')),
  client_uuid uuid not null,
  incident_id text references public.incident_report (incident_id) on delete cascade,
  report_id text references public.crowd_report (report_id) on delete cascade,
  storage_path text not null unique,
  uploaded_by uuid not null references auth.users (id) on delete cascade,
  uploaded_at timestamptz not null default now(),
  expired_at timestamptz,
  check ((kind = 'sos') = (incident_id is not null)),
  check ((kind = 'report') = (report_id is not null))
);
comment on table public.incident_photo is
  'Photos residents added to their SOS or crowd report (file in the incident-photos bucket). Hidden once expired_at is set (retention).';
create index incident_photo_incident_idx on public.incident_photo (incident_id);
create index incident_photo_report_idx on public.incident_photo (report_id);

-- The incident a photo belongs to: the SOS, or the report's cluster.
create function private.photo_incident(p_photo public.incident_photo)
returns text
language sql stable security definer set search_path = ''
as $$
  select coalesce(p_photo.incident_id,
                  (select c.incident_id from public.crowd_report c where c.report_id = p_photo.report_id))
$$;

-- Whether the signed-in account may see [p_photo].
create function private.can_see_photo(p_photo public.incident_photo)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select p_photo.expired_at is null and (
    private.is_dispatcher()
    or p_photo.uploaded_by = (select auth.uid())
    or exists (
      select 1 from public.incident_report i
       where i.incident_id = private.photo_incident(p_photo)
         and i.assigned_unit_id is not null
         and i.assigned_unit_id = private.current_staff_unit())
  )
$$;

-- The same, for a file in the bucket.
create function private.can_see_photo_file(p_path text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.incident_photo p
     where p.storage_path = p_path and private.can_see_photo(p))
$$;

revoke execute on function
  private.photo_incident(public.incident_photo),
  private.can_see_photo(public.incident_photo),
  private.can_see_photo_file(text)
  from public, anon;
-- Policies run as the caller, so signed-in users need these three.
grant execute on function
  private.can_see_photo(public.incident_photo),
  private.can_see_photo_file(text)
  to authenticated;

alter table public.incident_photo enable row level security;
create policy "incident photos: staff, the uploader, the assigned unit" on public.incident_photo
  for select to authenticated using ((select private.can_see_photo(incident_photo)));
grant select on public.incident_photo to authenticated;

-- The bucket: a resident adds files to their own folder only; reading
-- follows the photo rows; nobody updates or deletes from an app.
create policy "incident photos: a resident uploads into their own folder" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'incident-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select private.current_resident_id()) is not null
  );
create policy "incident photos: read as the photo rows allow" on storage.objects
  for select to authenticated
  using (bucket_id = 'incident-photos' and (select private.can_see_photo_file(name)));

-- Ties an uploaded file to the caller's own SOS ('sos') or crowd report
-- ('report'), by the record's client id. Sending it again changes nothing.
-- Refused: a record that is not the caller's or not on the server
-- (not_found), a closed SOS (incident_closed), a fourth photo
-- (invalid_value).
create function public.attach_photo(p_photo_id uuid, p_kind text, p_client_uuid uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  me public.manila_resident := private.require_resident();
  path text;
  sos public.incident_report;
  rep public.crowd_report;
begin
  if p_photo_id is null or p_client_uuid is null or p_kind is null
     or p_kind not in ('sos', 'report') then
    raise exception 'invalid_value' using errcode = 'P0001';
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

  if p_kind = 'sos' then
    select * into sos from public.incident_report i
     where i.client_uuid = p_client_uuid and i.manila_resident_id = me.manila_resident_id;
    if sos.incident_id is null then
      raise exception 'not_found' using errcode = 'P0001';
    end if;
    if sos.status = 'resolved' then
      raise exception 'incident_closed' using errcode = 'P0001';
    end if;
    if (select count(*) from public.incident_photo p
         where p.incident_id = sos.incident_id and p.expired_at is null) >= 3 then
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

-- The photos of an incident: its SOS's, and those of the reports in its
-- cluster, oldest first, each only if the caller may see it (a responder
-- cannot read crowd reports, but sees the photos of their unit's job).
create function public.incident_photos(p_incident_id text)
returns setof public.incident_photo
language sql stable security definer set search_path = ''
as $$
  select p.* from public.incident_photo p
   where (p.incident_id = p_incident_id
          or p.report_id in (select c.report_id from public.crowd_report c
                              where c.incident_id = p_incident_id))
     and private.can_see_photo(p)
   order by p.uploaded_at, p.photo_id
$$;
revoke execute on function public.incident_photos(text) from public, anon;
grant execute on function public.incident_photos(text) to authenticated;

-- Retention: an anonymized incident or report hides its photos.
create function private.expire_photos()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_table_name = 'incident_report' then
    update public.incident_photo set expired_at = now()
     where incident_id = new.incident_id and expired_at is null;
  else
    update public.incident_photo set expired_at = now()
     where report_id = new.report_id and expired_at is null;
  end if;
  return new;
end $$;
revoke execute on function private.expire_photos() from public, anon, authenticated;

create trigger incident_report_expire_photos
  after update of anonymized_at on public.incident_report
  for each row when (old.anonymized_at is null and new.anonymized_at is not null)
  execute function private.expire_photos();
create trigger crowd_report_expire_photos
  after update of anonymized_at on public.crowd_report
  for each row when (old.anonymized_at is null and new.anonymized_at is not null)
  execute function private.expire_photos();

-- The dashboard follows new photos.
alter publication supabase_realtime add table public.incident_photo;
