-- Incident posts are sent by their own function, post-incidents, so the
-- send-alerts function did not have to be redeployed for them
-- (2026-10-13). The queue's wake-up now calls it, with the same shared
-- secret from the vault. Without the vault secret it does nothing.

create function private.call_incident_poster()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_key text;
begin
  select s.decrypted_secret into v_key from vault.decrypted_secrets s where s.name = 'send_alerts_key';
  if v_key is null then
    return;
  end if;
  perform net.http_post(
    url := 'https://imssgenjfirpohkwxwbv.supabase.co/functions/v1/post-incidents',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-sagip-key', v_key),
    timeout_milliseconds := 10000);
end $$;

create or replace function private.wake_sender_for_incident_posts()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (select 1 from added a where a.status = 'queued') then
    perform private.call_incident_poster();
  end if;
  return null;
end $$;

revoke execute on function private.call_incident_poster() from public, anon, authenticated;
