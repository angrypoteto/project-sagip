-- Fix to crew_heads_requests (2026-10-29): a head or assistant taken off
-- their unit (unit set to none) stayed its lead, because comparing with a
-- null unit gives null, not "different". The RLS test caught it
-- ("and is no longer its head").

create or replace function private.clear_unit_leads()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.response_unit r set crew_head_id = null
   where r.crew_head_id = new.id
     and (new.role <> 'responder' or new.deactivated_at is not null
          or new.unit_id is distinct from r.unit_id);
  update public.response_unit r set assistant_head_id = null
   where r.assistant_head_id = new.id
     and (new.role <> 'responder' or new.deactivated_at is not null
          or new.unit_id is distinct from r.unit_id);
  return new;
end $$;
