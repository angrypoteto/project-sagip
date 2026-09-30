-- Configuration (A3) and the priority score in the database (plan 10.1, FR2).
--
-- app_setting holds values an administrator can change from the dashboard,
-- starting with the Triage Queue priority weights. They are provisional
-- until MDRRMD's triage SOP arrives (Table 3.1 item 4, plan Q15 and Q20).
-- Dispatchers and admins can read them; only admins change them, through
-- set_setting(), and every change is written to the audit log.
--
-- incident_board gains the score, its severity, and the factors behind it,
-- computed with the same rules as PriorityRules in packages/shared. The
-- dashboard ranks with those rules locally too (waiting time changes every
-- minute) using these weights.

-- ------------------------------------------------------------ settings

create table public.app_setting (
  key text primary key,
  category text not null check (category in ('priority')),
  value jsonb not null,
  min_value numeric,
  max_value numeric,
  description text not null,
  updated_at timestamptz not null default now(),
  updated_by text
);
comment on table public.app_setting is
  'Settings an administrator can change (A3). Change them with set_setting(), which audits.';

alter table public.app_setting enable row level security;
create policy "settings: dispatchers and admins" on public.app_setting
  for select to authenticated using ((select private.is_dispatcher()));
grant select on public.app_setting to authenticated;
alter publication supabase_realtime add table public.app_setting;

insert into public.app_setting (key, category, value, min_value, max_value, description) values
  ('priority.sos', 'priority', '50', 0, 200, 'Points for a single-person SOS'),
  ('priority.cluster', 'priority', '40', 0, 200, 'Points for a confirmed cluster of crowd reports'),
  ('priority.vulnerable', 'priority', '30', 0, 200, 'Points when the household has a vulnerable member'),
  ('priority.waiting_per_minute', 'priority', '2', 0, 20, 'Points for each minute of waiting'),
  ('priority.waiting_max', 'priority', '30', 0, 200, 'The most points waiting can add'),
  ('priority.mock_location', 'priority', '-20', -200, 0, 'Points for a suspected mock location (a penalty)'),
  ('priority.critical_at', 'priority', '80', 0, 500, 'Score at which an incident is Critical'),
  ('priority.high_at', 'priority', '50', 0, 500, 'Score at which an incident is High');

-- Setting changes are audited (FR11).
alter table public.audit_log drop constraint audit_log_action_type_check;
alter table public.audit_log add constraint audit_log_action_type_check check (action_type in (
  'verified', 'markedFalseReport', 'typeConfirmed', 'unitAssigned', 'unitReassigned',
  'statusChanged', 'resolved', 'smsCheckSent', 'contactViewed', 'settingChanged'
));

create or replace function private.setting_number(p_key text)
returns numeric
language sql stable security definer set search_path = ''
as $$ select (s.value #>> '{}')::numeric from public.app_setting s where s.key = p_key $$;

create or replace function public.set_setting(p_key text, p_value jsonb)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me public.staff;
  s public.app_setting;
  v numeric;
begin
  select * into me from public.staff st where st.id = (select auth.uid());
  if me.id is null or me.role <> 'admin' then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  select * into s from public.app_setting a where a.key = p_key for update;
  if s.key is null then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if p_value is null or jsonb_typeof(p_value) <> jsonb_typeof(s.value) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if jsonb_typeof(p_value) = 'number' then
    v := (p_value #>> '{}')::numeric;
    if (s.min_value is not null and v < s.min_value) or (s.max_value is not null and v > s.max_value) then
      raise exception 'invalid_value' using errcode = 'P0001';
    end if;
  end if;
  -- High must stay at or below Critical.
  if (p_key = 'priority.high_at' and v > private.setting_number('priority.critical_at'))
     or (p_key = 'priority.critical_at' and v < private.setting_number('priority.high_at')) then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  if s.value = p_value then
    return;
  end if;

  update public.app_setting
     set value = p_value, updated_at = now(), updated_by = me.display_name
   where key = p_key;
  insert into public.audit_log (account_id, account_name, account_role, action_type, target_table, target_id, detail)
  values (me.id::text, me.display_name, me.role, 'settingChanged', 'app_setting', p_key,
          (s.value #>> '{}') || ' → ' || (p_value #>> '{}'));
end $$;

revoke execute on function public.set_setting(text, jsonb) from public, anon;
grant execute on function public.set_setting(text, jsonb) to authenticated;

-- ------------------------------------------------------------ priority score

-- The Triage Queue score (plan 10.1): the same rules as PriorityRules.score
-- in packages/shared/lib/src/algorithms/priority.dart. Keep them in step.
create or replace function private.priority_breakdown(
  p_origin text,
  p_vulnerable text[],
  p_captured_at timestamptz,
  p_mock_location boolean,
  p_now timestamptz default now()
)
returns table (score numeric, severity text, factors jsonb)
language plpgsql stable security definer set search_path = ''
as $$
declare
  w jsonb;
  f jsonb := '[]'::jsonb;
  total numeric := 0;
  pts numeric;
  waiting numeric;
begin
  select jsonb_object_agg(s.key, s.value) into w
    from public.app_setting s where s.category = 'priority';

  if p_origin = 'sos' then
    pts := (w ->> 'priority.sos')::numeric;
    f := f || jsonb_build_array(jsonb_build_object('kind', 'sos', 'points', pts));
  else
    pts := (w ->> 'priority.cluster')::numeric;
    f := f || jsonb_build_array(jsonb_build_object('kind', 'cluster', 'points', pts));
  end if;
  total := total + pts;

  if coalesce(cardinality(p_vulnerable), 0) > 0 then
    pts := (w ->> 'priority.vulnerable')::numeric;
    f := f || jsonb_build_array(jsonb_build_object('kind', 'vulnerable', 'points', pts));
    total := total + pts;
  end if;

  -- Whole seconds, like Duration.inSeconds in Dart.
  waiting := least(
    greatest(floor(extract(epoch from (p_now - p_captured_at))) / 60
             * (w ->> 'priority.waiting_per_minute')::numeric, 0),
    (w ->> 'priority.waiting_max')::numeric);
  if waiting > 0 then
    pts := round(waiting);
    f := f || jsonb_build_array(jsonb_build_object('kind', 'waiting', 'points', pts));
    total := total + pts;
  end if;

  if p_mock_location then
    pts := (w ->> 'priority.mock_location')::numeric;
    f := f || jsonb_build_array(jsonb_build_object('kind', 'mockLocation', 'points', pts));
    total := total + pts;
  end if;

  return query select
    total,
    case
      when total >= (w ->> 'priority.critical_at')::numeric then 'critical'
      when total >= (w ->> 'priority.high_at')::numeric then 'high'
      else 'normal'
    end,
    f;
end $$;

revoke execute on function private.setting_number(text) from public, anon, authenticated;
revoke execute on function
  private.priority_breakdown(text, text[], timestamptz, boolean, timestamptz)
from public, anon;
-- The board view runs as the caller (security_invoker), so signed-in users
-- need to run the score; it reads only the weights.
grant execute on function
  private.priority_breakdown(text, text[], timestamptz, boolean, timestamptz)
to authenticated;

-- The board view gains the score, appended so existing readers keep working.
create or replace view public.incident_board with (security_invoker = true) as
select
  i.incident_id as id,
  i.origin, i.channel, i.status, i.suggested_type, i.emergency_type,
  i.latitude, i.longitude, i.barangay, i.district, i.address, i.accuracy_m,
  i.captured_at, i.received_at, i.manila_resident_id, i.people_count, i.note,
  i.vulnerable, i.account_verified, i.mock_location, i.verification_method,
  i.assigned_unit_id, i.suggestion_overridden, i.override_reason,
  i.false_report, i.resolved_at,
  coalesce(
    (select array_agg(c.report_id order by c.submitted_at)
       from public.crowd_report c where c.incident_id = i.incident_id),
    '{}'
  ) as crowd_report_ids,
  coalesce(
    (select jsonb_agg(jsonb_build_object(
        'kind', e.kind, 'at', e.at, 'actor_name', e.actor_name, 'detail', e.detail
      ) order by e.at, e.event_id)
       from public.incident_event e where e.incident_id = i.incident_id),
    '[]'::jsonb
  ) as events,
  p.score as priority_score,
  p.severity as priority_severity,
  p.factors as priority_factors
from public.incident_report i
cross join lateral private.priority_breakdown(i.origin, i.vulnerable, i.captured_at, i.mock_location) p;
