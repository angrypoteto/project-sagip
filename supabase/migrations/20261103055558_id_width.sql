-- Found by the surge test (NFR7, 2026-11-03): three record numbers were
-- built with lpad(n, width), and lpad cuts a longer number down to the
-- width. The 1,000th resident got 'res-100' (taken), so every registration
-- after the 999th would fail; incident 10,000 would become 'INC-1000' and
-- clash the same way, inside the 10,000-an-hour surge NFR7 names; NDRRMC
-- report 10,000 likewise. Now the number is padded to at least the width
-- and never cut: res-999, res-1000; INC-9999, INC-10000. Existing numbers
-- keep their form. Crowd reports ('rep-' and the plain number) were fine.

create or replace function private.padded_number(p_prefix text, p_n bigint, p_width int)
returns text
language sql
immutable
set search_path = ''
as $$
  select p_prefix || lpad(p_n::text, greatest(p_width, length(p_n::text)), '0');
$$;

revoke all on function private.padded_number(text, bigint, int) from public, anon, authenticated;

alter table public.manila_resident
  alter column manila_resident_id set default private.padded_number('res-', nextval('public.resident_number_seq'), 3);
alter table public.incident_report
  alter column incident_id set default private.padded_number('INC-', nextval('public.incident_number_seq'), 4);
alter table public.ndrrmc_report
  alter column report_id set default private.padded_number('RPT-', nextval('public.ndrrmc_report_number_seq'), 4);
