-- Data retention (A3 Configuration; RA 10173; Joshua decided on 2026-10-11:
-- an administrator sets the period, one year by default).
--
-- Once an incident has been closed for longer than the period, what points
-- at a person is removed from it, every night:
--   - the link to the resident, their note, the address, the cancel note;
--   - the exact position: rounded to three decimals (about 110 m, the size
--     of the forecast's grid cell), so the barangay counts and the KDE
--     training data still hold, but the house can no longer be found;
--   - the position the phone sent while the SOS was open;
--   - what the resident was told about it (rescue confirmations) and the
--     SMS checks texted to them.
-- Crowd reports older than the period lose the link to the resident and
-- their exact position the same way. Their text is kept: the classifier is
-- trained on it (FR12), and it is about the hazard.
-- The texts log (sms_log: full numbers) is emptied of rows older than the
-- period.
-- Kept: the incident itself (type, barangay, times, status, unit), the
-- timeline, dispatch records, completion reports, and the audit log, which
-- NDRRMC reporting and accountability need. Open incidents are never
-- touched. Each night's run is audited as "System".

alter table public.app_setting drop constraint app_setting_category_check;
alter table public.app_setting add constraint app_setting_category_check
  check (category in ('priority', 'reports', 'alerts', 'channels', 'contact', 'demo', 'privacy'));

insert into public.app_setting (key, category, value, min_value, max_value, description) values
  ('privacy.retention_months', 'privacy', '12', 6, 60,
   'Months after an incident is closed before personal details are removed from it');

alter table public.incident_report add column anonymized_at timestamptz;
alter table public.crowd_report add column anonymized_at timestamptz;

alter table public.audit_log drop constraint audit_log_action_type_check;
alter table public.audit_log add constraint audit_log_action_type_check check (action_type in (
  'verified', 'markedFalseReport', 'typeConfirmed', 'unitAssigned', 'unitReassigned',
  'statusChanged', 'resolved', 'smsCheckSent', 'contactViewed', 'settingChanged',
  'unitAdded', 'unitEdited', 'unitRetired', 'unitRestored', 'rosterChanged',
  'accountCreated', 'accountUpdated', 'accountDeactivated', 'accountReactivated',
  'passwordReset', 'residentSuspended', 'residentRestored', 'weatherSimulated',
  'alertIssued', 'alertEnded', 'reportDrafted', 'reportFinalized',
  'sosSimulated', 'reportsSimulated', 'sosCancelled', 'retentionApplied'
));

-- Removes personal details older than the retention period. Returns what
-- it did. Runs from pg_cron; nobody else may call it.
create function private.apply_retention()
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_months int := coalesce(private.setting_number('privacy.retention_months'), 12)::int;
  v_cutoff timestamptz;
  v_ids text[];
  v_incidents int := 0;
  v_reports int := 0;
  v_texts int := 0;
begin
  -- Never shorter than the setting's own floor, whatever the table says.
  v_months := greatest(v_months, 6);
  v_cutoff := now() - make_interval(months => v_months);

  with done as (
    update public.incident_report i
       set manila_resident_id = null,
           note = null,
           address = null,
           cancel_note = null,
           accuracy_m = null,
           latitude = round(i.latitude::numeric, 3)::double precision,
           longitude = round(i.longitude::numeric, 3)::double precision,
           last_latitude = null,
           last_longitude = null,
           last_accuracy_m = null,
           last_location_at = null,
           anonymized_at = now()
     where i.status = 'resolved'
       and i.resolved_at < v_cutoff
       and i.anonymized_at is null
    returning i.incident_id
  )
  select coalesce(array_agg(incident_id), '{}') into v_ids from done;
  v_incidents := cardinality(v_ids);

  if v_incidents > 0 then
    delete from public.rescue_confirmation c where c.incident_id = any (v_ids);
    delete from public.sms_check c where c.incident_id = any (v_ids);
  end if;

  with done as (
    update public.crowd_report c
       set manila_resident_id = null,
           latitude = round(c.latitude::numeric, 3)::double precision,
           longitude = round(c.longitude::numeric, 3)::double precision,
           anonymized_at = now()
     where c.submitted_at < v_cutoff
       and c.anonymized_at is null
       -- A report in a cluster that is still open waits for it to close.
       and not exists (
             select 1 from public.incident_report i
              where i.incident_id = c.incident_id and i.status <> 'resolved')
    returning 1
  )
  select count(*) into v_reports from done;

  with done as (
    delete from public.sms_log l where l.created_at < v_cutoff returning 1
  )
  select count(*) into v_texts from done;

  if v_incidents + v_reports + v_texts > 0 then
    insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id, detail)
    values ('system', 'System', 'system', 'retentionApplied', 'incident_report', 'retention',
            format('%s months: %s incidents, %s crowd reports, %s texts', v_months, v_incidents, v_reports, v_texts));
  end if;
  return jsonb_build_object(
    'months', v_months, 'incidents', v_incidents, 'crowd_reports', v_reports, 'texts', v_texts);
end $$;

revoke all on function private.apply_retention() from public, anon, authenticated;

-- Every night at 03:15 in Manila (19:15 UTC).
select cron.schedule('apply-retention', '15 19 * * *', 'select private.apply_retention()');
