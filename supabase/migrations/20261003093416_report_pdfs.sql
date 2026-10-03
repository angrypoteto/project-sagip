-- Final NDRRMC reports keep their PDF (plan 10.6: "PDF export ... to
-- Storage and a report record"; A6).
--
-- A private Storage bucket, `ndrrmc-reports`, holds one file per final
-- report, named `<report id>.pdf`. Only active admins may read it, and may
-- add a report's file only once the report is final and only once: there
-- is no update or delete policy, so the stored copy stays as issued.
-- attach_report_pdf() records on the report that its file is stored.

alter table public.ndrrmc_report add column pdf_stored_at timestamptz;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ndrrmc-reports', 'ndrrmc-reports', false, 10485760, array['application/pdf'])
on conflict (id) do nothing;

create policy "ndrrmc pdfs: admins read" on storage.objects
  for select to authenticated
  using (bucket_id = 'ndrrmc-reports' and private.is_admin());

create policy "ndrrmc pdfs: admins add a final report's file once" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'ndrrmc-reports'
    and private.is_admin()
    and exists (
      select 1 from public.ndrrmc_report r
       where r.status = 'final' and r.pdf_stored_at is null
         and name = r.report_id || '.pdf'
    )
  );

-- Marks the report's PDF as stored, once its file is in the bucket.
create function public.attach_report_pdf(p_report_id text)
returns timestamptz
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := private.require_admin();
  r public.ndrrmc_report;
begin
  select * into r from public.ndrrmc_report where report_id = p_report_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if r.status <> 'final' then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if r.pdf_stored_at is not null then
    return r.pdf_stored_at;
  end if;
  if not exists (
    select 1 from storage.objects o
     where o.bucket_id = 'ndrrmc-reports' and o.name = p_report_id || '.pdf'
  ) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  update public.ndrrmc_report set pdf_stored_at = now() where report_id = p_report_id;
  return now();
end $$;

revoke execute on function public.attach_report_pdf(text) from public, anon;
grant execute on function public.attach_report_pdf(text) to authenticated;
