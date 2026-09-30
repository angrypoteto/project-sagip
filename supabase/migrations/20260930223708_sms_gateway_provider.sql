-- Inbound texts forwarded by the MDRRMD gateway SIM (sms-intake) are logged
-- with provider 'gateway'.
alter table public.sms_log drop constraint sms_log_provider_check;
alter table public.sms_log add constraint sms_log_provider_check
  check (provider in ('semaphore', 'dev', 'gateway'));
