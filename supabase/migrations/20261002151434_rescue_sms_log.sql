-- The text that tells a resident a unit was assigned to their SOS (FR6)
-- gets its own kind in the SMS log, so the log tells it apart from the
-- acknowledgement of an SOS received by SMS ("ack").
--
-- The only change is one more allowed kind.

alter table public.sms_log drop constraint sms_log_kind_check;
alter table public.sms_log add constraint sms_log_kind_check
  check (kind in ('otp', 'alert', 'ack', 'inbound', 'rescue'));
