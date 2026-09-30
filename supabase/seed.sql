-- Demo data for a local database (`supabase db reset` runs this after the
-- migrations). The data itself lives in public.reset_demo_data() so the
-- hosted project can be reset the same way from the SQL editor.
--
-- Staff accounts are not seeded: their passwords must not be in the repo.
-- Create them once with public.create_staff_account(...) (see README.md).
select public.reset_demo_data();
