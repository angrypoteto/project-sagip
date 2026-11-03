-- Follow-up to sos_repeat_joins (2026-11-03). submit_sos now looks for the
-- account's open SOS before adding one; without an index that read every
-- incident, so an SOS slowed as incidents piled up (2 ms at the start of a
-- 10,000-SOS surge, 5.6 ms by the end, in a rolled-back run). With it the
-- lookup is direct: 0.9 ms an SOS, flat, in the same run.

create index if not exists incident_report_open_by_resident_idx
  on public.incident_report (manila_resident_id, received_at)
  where status <> 'resolved';
