-- D4: what the resident was told about their SOS (FR6), on the incident
-- drawer. Dispatchers could already read `rescue_confirmation`; whether the
-- push went out lives in `push_message`, which only the service role reads.
-- `incident_notices` joins the two for dispatchers and admins, without the
-- push text, tokens, or anything else about the resident's phone.
--
-- Everything here is added; nothing existing changes.

-- The push for a confirmation carries its id in `data` (queue_rescue_push).
create index push_message_confirmation_idx
  on public.push_message ((data ->> 'confirmation_id'))
  where kind = 'rescue';

-- One row per confirmation, oldest first. push_status is null when the
-- resident has no app account (registered by MDRRMD, or an SOS by SMS from
-- a number with no account), so no push was ever queued.
create or replace function public.incident_notices(p_incident_id text)
returns table (
  confirmation_id bigint,
  kind text,
  unit_call_sign text,
  created_at timestamptz,
  read_at timestamptz,
  sms_status text,
  push_status text
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public._require_dispatcher();
  return query
    select c.confirmation_id, c.kind, c.unit_call_sign, c.created_at, c.read_at,
           c.sms_status,
           (select m.status from public.push_message m
             where m.kind = 'rescue'
               and m.data ->> 'confirmation_id' = c.confirmation_id::text
             order by m.message_id desc limit 1)
      from public.rescue_confirmation c
     where c.incident_id = p_incident_id
     order by c.created_at, c.confirmation_id;
end $$;

revoke all on function public.incident_notices(text) from public, anon;
grant execute on function public.incident_notices(text) to authenticated;
