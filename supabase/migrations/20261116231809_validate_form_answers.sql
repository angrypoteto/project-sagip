-- MDRRMD corrects the form's answers when it validates a crew report
-- (2026-11-17): the crew's report now holds MDRRMD's EMR, flood and fire
-- form answers and a narrative, and MDRRMD validates that report, so it can
-- correct them as it already could the figures. p_details replaces the
-- answers (checked as on submit); p_narrative replaces the narrative. Either
-- left null keeps the crew's. A change marks the report corrected.

drop function public.validate_crew_report(uuid, text, int, int, int, int, int);

create function public.validate_crew_report(
  p_report_id uuid,
  p_outcome text default null,
  p_persons_assisted int default null,
  p_injured int default null,
  p_missing int default null,
  p_affected_families int default null,
  p_houses_damaged int default null,
  p_details jsonb default null,
  p_narrative text default null
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff := public._require_dispatcher();
  rep public.completion_report;
  inc public.incident_report;
  v_outcome text;
  v_details jsonb;
  v_narrative text;
  v_corrected boolean;
  v_call text;
begin
  select * into rep from public.completion_report c where c.report_id = p_report_id for update;
  if rep.report_id is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if rep.validated_at is not null then
    raise exception 'already_validated' using errcode = 'P0001';
  end if;
  if (p_outcome is not null
        and p_outcome not in ('rescued', 'treated', 'transported', 'noOneFound', 'falseReport'))
     or least(p_persons_assisted, p_injured, p_missing, p_affected_families, p_houses_damaged) < 0
     or (p_details is not null and not private.valid_completion_details(p_details))
     or length(p_narrative) > 2000 then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  v_outcome := coalesce(p_outcome, rep.outcome);
  v_details := coalesce(p_details, rep.details);
  v_narrative := case when p_narrative is null then rep.narrative else nullif(btrim(p_narrative), '') end;
  v_corrected := v_outcome <> rep.outcome
    or coalesce(p_persons_assisted, rep.persons_assisted) <> rep.persons_assisted
    or coalesce(p_injured, rep.injured) <> rep.injured
    or coalesce(p_missing, rep.missing) <> rep.missing
    or coalesce(p_affected_families, rep.affected_families) <> rep.affected_families
    or coalesce(p_houses_damaged, rep.houses_damaged) <> rep.houses_damaged
    or v_details <> rep.details
    or v_narrative is distinct from rep.narrative;
  update public.completion_report
     set outcome = v_outcome,
         persons_assisted = coalesce(p_persons_assisted, persons_assisted),
         injured = coalesce(p_injured, injured),
         missing = coalesce(p_missing, missing),
         affected_families = coalesce(p_affected_families, affected_families),
         houses_damaged = coalesce(p_houses_damaged, houses_damaged),
         details = v_details,
         narrative = v_narrative,
         corrected = v_corrected,
         validated_at = now(),
         validated_by = me.id,
         validated_by_name = me.display_name
   where report_id = rep.report_id;

  v_call := private.call_sign(rep.unit_id);
  insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id, detail)
  values (me.id::text, me.display_name, me.role, 'reportValidated', 'completion_report', rep.incident_id,
          v_call || case when v_corrected then ' (corrected)' else '' end);

  select * into inc from public.incident_report i where i.incident_id = rep.incident_id for update;
  insert into public.incident_event (incident_id, kind, actor_name, detail)
  values (inc.incident_id, 'reportValidated', me.display_name,
          v_call || case when v_corrected then ' (corrected)' else '' end);
  if inc.status <> 'resolved' then
    perform private.release_unit_from(rep.unit_id, inc.incident_id);
    perform public._close_dispatch(inc.incident_id);
    update public.incident_report
       set status = 'resolved', resolved_at = now(), false_report = (v_outcome = 'falseReport')
     where incident_id = inc.incident_id;
    insert into public.incident_event (incident_id, kind, actor_name, detail)
    values (inc.incident_id,
            case when v_outcome = 'falseReport' then 'markedFalseReport' else 'resolved' end,
            me.display_name, v_outcome);
  end if;
end $$;
revoke execute on function
  public.validate_crew_report(uuid, text, int, int, int, int, int, jsonb, text) from public, anon;
grant execute on function
  public.validate_crew_report(uuid, text, int, int, int, int, int, jsonb, text) to authenticated;
