-- NFR4 (RA 10173, keep personal data no longer than needed; Joshua,
-- 2026-11-03: "make the system now 100%"). The retention job hides the
-- photos of anonymized incidents (incident_photo.expired_at), but the files
-- stayed in the incident-photos bucket. Supabase does not let SQL delete
-- storage files, so the edge function purge-photos does it through the
-- Storage API, daily, half an hour after apply-retention:
--
-- 1. incident_photo.file_removed_at: when the file was deleted.
-- 2. expired_photo_files(), mark_photo_files_removed(): the function's two
--    calls; the service role only.
-- 3. private.call_purge_photos() and the cron job purge-photos (19:45 UTC,
--    3:45 AM in Manila), with the shared secret, as the other jobs.

alter table public.incident_photo add column file_removed_at timestamptz;

comment on column public.incident_photo.file_removed_at is
  'When the file was deleted from the incident-photos bucket (purge-photos), after the photo expired.';

create or replace function public.expired_photo_files(p_limit int default 100)
returns table (photo_id uuid, storage_path text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.photo_id, p.storage_path
    from public.incident_photo p
   where p.expired_at is not null and p.file_removed_at is null
   order by p.expired_at, p.photo_id
   limit greatest(1, least(coalesce(p_limit, 100), 500));
$$;

create or replace function public.mark_photo_files_removed(p_photo_ids uuid[])
returns int
language sql
security definer
set search_path = ''
as $$
  with done as (
    update public.incident_photo
       set file_removed_at = now()
     where photo_id = any(coalesce(p_photo_ids, '{}'))
       and expired_at is not null and file_removed_at is null
    returning 1)
  select count(*)::int from done;
$$;

revoke all on function public.expired_photo_files(int) from public, anon, authenticated;
revoke all on function public.mark_photo_files_removed(uuid[]) from public, anon, authenticated;
grant execute on function public.expired_photo_files(int) to service_role;
grant execute on function public.mark_photo_files_removed(uuid[]) to service_role;

create or replace function private.call_purge_photos()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  -- Nothing to delete: no call.
  if not exists (select 1 from public.incident_photo
                  where expired_at is not null and file_removed_at is null) then
    return;
  end if;
  select s.decrypted_secret into v_key from vault.decrypted_secrets s where s.name = 'send_alerts_key';
  if v_key is null then
    return;
  end if;
  perform net.http_post(
    url := 'https://imssgenjfirpohkwxwbv.supabase.co/functions/v1/purge-photos',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-sagip-key', v_key),
    timeout_milliseconds := 60000);
end $$;

revoke all on function private.call_purge_photos() from public, anon, authenticated;

select cron.schedule('purge-photos', '45 19 * * *', 'select private.call_purge_photos()');
