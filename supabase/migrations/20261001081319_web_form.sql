-- Resident web form (W1 to W3, FR15): crowd reports from a browser.
--
-- The web form signs residents in the same way as the app (mobile number
-- and a code) and calls the same checked function, so the Manila check, the
-- hourly limit, the suspension check, and DBSCAN all apply. This migration
-- records which channel a report came from, moves the hourly limit into
-- app_setting so an administrator sets it on A3, and tells the resident how
-- many reports they have left this hour. The web form never sends an SOS;
-- it only calls submit_crowd_report.

-- ------------------------------------------------------------ the limit (A3)

alter table public.app_setting drop constraint app_setting_category_check;
alter table public.app_setting add constraint app_setting_category_check
  check (category in ('priority', 'reports'));

insert into public.app_setting (key, category, value, min_value, max_value, description) values
  ('reports.per_hour', 'reports', '5', 1, 30,
   'Crowd reports one account may send in an hour (app and web form together)');

-- ------------------------------------------------------------ sending

-- A new parameter needs a new function: drop the old signature so the API
-- has one submit_crowd_report. Calls without p_source still work ('app').
drop function public.submit_crowd_report(
  uuid, timestamptz, text, text, double precision, double precision, double precision, text, text);

-- R4 and W2: a hazard report. Inside Manila; at most reports.per_hour an
-- hour per account counted by capture time, across the app and the web
-- form; and a hard cap of twice that received per hour, so back-dated
-- capture times cannot get around it. DBSCAN runs in the insert trigger.
create function public.submit_crowd_report(
  p_client_uuid uuid,
  p_captured_at timestamptz,
  p_description text,
  p_type text default null,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_accuracy_m double precision default null,
  p_barangay text default null,
  p_district text default null,
  p_source text default 'app'
)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  me public.manila_resident := private.require_resident();
  t timestamptz := private.capture_time(p_captured_at);
  lim int := coalesce(private.setting_number('reports.per_hour'), 5)::int;
  existing public.crowd_report;
  new_id text;
begin
  if p_client_uuid is null
     or coalesce(length(btrim(p_description)), 0) = 0 or length(p_description) > 500
     or (p_type is not null and p_type not in ('flood', 'fire', 'medical', 'structural'))
     or p_source is null or p_source not in ('app', 'webForm') then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;

  select * into existing from public.crowd_report c where c.client_uuid = p_client_uuid;
  if existing.report_id is not null then
    if existing.manila_resident_id is distinct from me.manila_resident_id then
      raise exception 'not_allowed' using errcode = 'P0001';
    end if;
    return existing.report_id;
  end if;

  if p_latitude is null or p_longitude is null then
    raise exception 'no_location' using errcode = 'P0001';
  end if;
  if not private.inside_manila(p_latitude, p_longitude) then
    raise exception 'outside_manila' using errcode = 'P0001';
  end if;
  if (select count(*) from public.crowd_report c
       where c.manila_resident_id = me.manila_resident_id
         and c.captured_at > t - interval '1 hour' and c.captured_at <= t) >= lim
     or (select count(*) from public.crowd_report c
          where c.manila_resident_id = me.manila_resident_id
            and c.submitted_at > now() - interval '1 hour') >= lim * 2 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  begin
    insert into public.crowd_report (
      client_uuid, manila_resident_id, description, reported_type,
      latitude, longitude, accuracy_m, barangay, district, source, captured_at
    ) values (
      p_client_uuid, me.manila_resident_id, btrim(p_description), p_type,
      p_latitude, p_longitude, p_accuracy_m,
      coalesce(nullif(btrim(p_barangay), ''), me.barangay),
      case when nullif(btrim(p_barangay), '') is null then me.district
           else coalesce(nullif(btrim(p_district), ''), me.district) end,
      p_source, t
    ) returning report_id into new_id;
  exception when unique_violation then
    select c.report_id into new_id from public.crowd_report c where c.client_uuid = p_client_uuid;
  end;
  return new_id;
end $$;

-- W2: how many reports the resident may still send this hour, when the
-- next one frees up, and whether the account is suspended (so the form can
-- say so before the resident writes a report).
create or replace function public.my_report_quota()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  me public.manila_resident := private.require_resident();
  lim int := coalesce(private.setting_number('reports.per_hour'), 5)::int;
  used int;
  oldest timestamptz;
begin
  select count(*), min(c.captured_at) into used, oldest
    from public.crowd_report c
   where c.manila_resident_id = me.manila_resident_id
     and c.captured_at > now() - interval '1 hour';
  return jsonb_build_object(
    'limit', lim,
    'used', used,
    'remaining', greatest(lim - used, 0),
    'resets_at', case when used >= lim then oldest + interval '1 hour' end,
    'suspended', me.suspended_at is not null);
end $$;

-- R6 and W3: the resident's reports now say which channel sent each one
-- (appended, so existing readers keep working).
create or replace function public.my_crowd_reports()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(x.row order by x.captured_at desc), '[]'::jsonb)
  from (
    select c.captured_at, jsonb_build_object(
      'client_id', coalesce(c.client_uuid::text, c.report_id),
      'captured_at', c.captured_at,
      'description', c.description,
      'type', coalesce(c.reported_type, c.category),
      'latitude', c.latitude,
      'longitude', c.longitude,
      'accuracy_m', c.accuracy_m,
      'barangay', c.barangay,
      'district', c.district,
      'delivery', 'delivered',
      'delivered_at', c.submitted_at,
      'server_id', c.report_id,
      'stage', case
                 when i.incident_id is not null and i.status = 'resolved' then 'resolved'
                 when i.incident_id is not null then 'confirmed'
                 when c.captured_at < now() - interval '60 minutes' then 'notConfirmed'
                 else 'checking'
               end,
      'incident_id', c.incident_id,
      'source', c.source
    ) as row
    from public.crowd_report c
    left join public.incident_report i on i.incident_id = c.incident_id
    where c.manila_resident_id = (select private.current_resident_id())
    order by c.captured_at desc
    limit 200
  ) x
$$;

-- ------------------------------------------------------------ privileges

revoke execute on function
  public.submit_crowd_report(uuid, timestamptz, text, text, double precision, double precision, double precision, text, text, text),
  public.my_report_quota()
from public, anon;

grant execute on function
  public.submit_crowd_report(uuid, timestamptz, text, text, double precision, double precision, double precision, text, text, text),
  public.my_report_quota()
to authenticated;
