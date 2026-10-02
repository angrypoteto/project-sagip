-- Wakes the send-alerts Edge Function whenever something is queued for it:
-- an alert delivery, a rescue text, or a push (FR6, FR14; plan part 7). No
-- Database Webhook has to be made by hand in the dashboard.
--
-- - pg_net makes the HTTP call after the transaction commits, so a rolled
--   back change calls nothing.
-- - The shared secret is made here, at random, in Supabase Vault; it is
--   never in the repo. The function reads the same value through
--   sender_secret(), which only the service role may call.
-- - One call per statement, and only when the statement queued something.
--   A call with nothing to send does nothing, so an extra one is harmless.
--
-- Everything here is added; nothing existing changes.

create extension if not exists pg_net with schema extensions;

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'send_alerts_key') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'send_alerts_key',
      'Shared secret between the database and the send-alerts Edge Function');
  end if;
end $$;

-- For the function only.
create or replace function public.sender_secret()
returns text
language sql stable security definer set search_path = ''
as $$
  select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'send_alerts_key'
$$;

-- The call itself. The address is this project's function (not a secret;
-- it is in supabase/README.md). Without the vault secret it does nothing.
create or replace function private.call_sender()
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
    url := 'https://imssgenjfirpohkwxwbv.supabase.co/functions/v1/send-alerts',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-sagip-key', v_key),
    timeout_milliseconds := 10000);
end $$;

create or replace function private.wake_sender_for_alerts()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (select 1 from added a where a.status = 'queued') then
    perform private.call_sender();
  end if;
  return null;
end $$;

create or replace function private.wake_sender_for_rescue_texts()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (select 1 from added a where a.sms_status = 'queued') then
    perform private.call_sender();
  end if;
  return null;
end $$;

create or replace function private.wake_sender_for_pushes()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (select 1 from added a where a.status = 'queued') then
    perform private.call_sender();
  end if;
  return null;
end $$;

create trigger alert_delivery_wake_sender
  after insert on public.alert_delivery
  referencing new table as added
  for each statement execute function private.wake_sender_for_alerts();

create trigger rescue_confirmation_wake_sender
  after insert on public.rescue_confirmation
  referencing new table as added
  for each statement execute function private.wake_sender_for_rescue_texts();

create trigger push_message_wake_sender
  after insert on public.push_message
  referencing new table as added
  for each statement execute function private.wake_sender_for_pushes();

revoke execute on function
  private.call_sender(), private.wake_sender_for_alerts(),
  private.wake_sender_for_rescue_texts(), private.wake_sender_for_pushes()
from public, anon, authenticated;

revoke execute on function public.sender_secret() from public, anon, authenticated;
grant execute on function public.sender_secret() to service_role;
