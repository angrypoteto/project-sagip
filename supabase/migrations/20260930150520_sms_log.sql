-- SMS log (part 6c): every text S.A.G.I.P. sends or tries to send, starting
-- with sign-in codes from the Send SMS hook (supabase/functions/send-sms).
-- Semaphore broadcasts and SOS acknowledgements will log here too (plan
-- Phase 5 and 6: "a delivery log").
--
-- Clients cannot read it at all: it holds full numbers. It is for the SQL
-- editor and Table Editor. While no SMS provider is set up, the hook keeps
-- the sign-in message (with the code) here instead of sending it, so the
-- demo can be run; those rows are deleted after an hour.

create table public.sms_log (
  log_id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  kind text not null check (kind in ('otp', 'alert', 'ack')),
  to_number text not null,
  body text not null,
  provider text not null check (provider in ('semaphore', 'dev')),
  status text not null check (status in ('sent', 'failed', 'notSent')),
  detail text
);
comment on table public.sms_log is
  'Texts sent or kept by S.A.G.I.P. Full numbers: SQL editor only, no client access.';
create index sms_log_created_idx on public.sms_log (created_at desc);

alter table public.sms_log enable row level security;
-- No policies and no grants: only the service role and the SQL editor.

-- Development sign-in codes do not stay around.
create or replace function private.expire_dev_codes()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.sms_log
   where kind = 'otp' and provider = 'dev' and created_at < now() - interval '1 hour';
  return null;
end $$;

create trigger sms_log_expire_dev_codes
  after insert on public.sms_log
  for each statement execute function private.expire_dev_codes();

revoke execute on function private.expire_dev_codes() from public, anon, authenticated;
