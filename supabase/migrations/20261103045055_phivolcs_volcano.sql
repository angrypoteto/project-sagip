-- FR14 (Joshua, 2026-11-03: "make the system now 100%"): PHIVOLCS Volcano
-- Alert Level changes are pulled and passed on to residents, with the
-- ashfall guidance the thesis names (wear a face mask). PHIVOLCS has no
-- API; ingest-phivolcs reads the alert levels from the header of its
-- bulletin list (https://wovodat.phivolcs.dost.gov.ph/bulletin/list-of-bulletin)
-- every 15 minutes with the earthquakes. Ashfall advisories are not
-- published as a separate feed, so the guidance rides on the level change.
--
-- 1. volcano_status: each volcano's current level, when it last changed,
--    and the level before (dispatchers and admins read it; D10).
-- 2. record_volcano_levels(): the service role's call. The first reading of
--    a volcano is only stored. A later change of Taal or Pinatubo, the two
--    whose ash can reach Manila, where the old or new level is 2 or more
--    (1 is the long-standing "low-level unrest"), becomes one alert for all
--    of Manila: info, or warning when raised to 3 or more; in the app and by
--    push only, as the earthquake notices; ending after 72 hours, or when
--    the next change replaces it.
-- 3. Setting alerts.volcano_relay (on): A3, beside the earthquake switch.

create table public.volcano_status (
  code text primary key check (code ~ '^[a-z]{2,6}$'),
  volcano text not null check (length(volcano) between 1 and 40),
  alert_level smallint not null check (alert_level between 0 and 5),
  previous_level smallint check (previous_level between 0 and 5),
  changed_at timestamptz,
  seen_at timestamptz not null default now(),
  relayed_alert_id text references public.public_alert (alert_id)
);

comment on table public.volcano_status is
  'PHIVOLCS Volcano Alert Level per volcano, from its bulletin list (ingest-phivolcs). FR14.';

alter table public.volcano_status enable row level security;
create policy "volcano status: dispatchers and admins" on public.volcano_status
  for select to authenticated using ((select private.is_dispatcher()));
grant select on public.volcano_status to authenticated;
alter publication supabase_realtime add table public.volcano_status;

insert into public.app_setting (key, category, value, min_value, max_value, description) values
  ('alerts.volcano_relay', 'alerts', 'true', null, null,
   'A change in the PHIVOLCS alert level of Taal or Pinatubo is passed on to residents, with ashfall guidance, in the app and by push')
on conflict (key) do nothing;

create or replace function public.record_volcano_levels(p_levels jsonb)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v record;
  old public.volcano_status;
  n int := 0;
  new_id text;
  raised boolean;
  meaning text;
begin
  if jsonb_typeof(p_levels) <> 'array' then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  for v in
    select lower(e ->> 'code') as code, left(e ->> 'volcano', 40) as volcano,
           (e ->> 'level')::smallint as level
      from jsonb_array_elements(p_levels) e
     where (e ->> 'level') ~ '^[0-5]$' and lower(e ->> 'code') ~ '^[a-z]{2,6}$'
  loop
    select * into old from public.volcano_status s where s.code = v.code for update;
    if old.code is null then
      insert into public.volcano_status (code, volcano, alert_level) values (v.code, v.volcano, v.level);
      continue;
    end if;
    if old.alert_level = v.level then
      update public.volcano_status set seen_at = now(), volcano = v.volcano where code = v.code;
      continue;
    end if;
    raised := v.level > old.alert_level;
    new_id := null;
    -- The notice about the level before ends now: the new level replaces it.
    update public.public_alert set expires_at = now()
     where alert_id = old.relayed_alert_id and (expires_at is null or expires_at > now());
    if coalesce(private.setting_flag('alerts.volcano_relay'), false)
       and v.code in ('tvo', 'pvo')
       and greatest(v.level, old.alert_level) >= 2 then
      meaning := case v.level
        when 0 then 'normal' when 1 then 'low-level unrest' when 2 then 'increasing unrest'
        when 3 then 'magmatic unrest' when 4 then 'hazardous eruption imminent'
        else 'hazardous eruption in progress' end;
      insert into public.public_alert
        (source, level, title, body, guidance, barangays, expires_at, is_simulated)
      values (
        'phivolcs',
        case when raised and v.level >= 3 then 'warning' else 'info' end,
        format('%s Volcano: Alert Level %s', v.volcano, v.level),
        case when raised then
          format('PHIVOLCS raised %s Volcano from Alert Level %s to %s (%s). '
                 'If it erupts, ash may fall on Manila depending on the wind.',
                 v.volcano, old.alert_level, v.level, meaning)
        else
          format('PHIVOLCS lowered %s Volcano from Alert Level %s to %s (%s).',
                 v.volcano, old.alert_level, v.level, meaning)
        end,
        case when raised then
          array['Keep a face mask ready; wear it or a damp cloth if ash falls',
                'If ash falls, stay indoors and keep windows and doors closed',
                'Follow PHIVOLCS and MDRRMD for updates']
        else
          array['Follow PHIVOLCS and MDRRMD for updates']
        end,
        '{}', now() + interval '72 hours',
        coalesce(private.setting_flag('demo.simulation'), false))
      returning alert_id into new_id;
      -- In the app and by push, as the earthquake notices.
      update public.alert_delivery set status = 'off'
       where alert_id = new_id and channel in ('sms', 'facebook') and status = 'queued';
      n := n + 1;
    end if;
    update public.volcano_status
       set volcano = v.volcano, previous_level = old.alert_level, alert_level = v.level,
           changed_at = now(), seen_at = now(), relayed_alert_id = new_id
     where code = v.code;
  end loop;
  return n;
end $$;

revoke all on function public.record_volcano_levels(jsonb) from public, anon, authenticated;
grant execute on function public.record_volcano_levels(jsonb) to service_role;
