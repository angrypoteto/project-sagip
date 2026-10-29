-- Hotspots (Joshua, 2026-10-29): the KDE's density per barangay and hazard,
-- shown as a heat map on the dashboard's Heatmap page beside the 72-hour
-- forecast, so "where incidents usually happen" is never mistaken for
-- "what is forecast".
--
-- One row per barangay and hazard: the barangay's mean density on the
-- 100 m grid divided by the densest barangay's (kde.py, thesis: Gaussian
-- kernel, haversine, bandwidth by 5-fold CV, grid averaged per barangay).
-- Replaced whole each time the KDE is fitted again (the export from
-- ml/forecast/kde). Barangays with no row have no density.
--
-- Dispatchers and admins read it; no client writes it.

create table public.hazard_density (
  barangay text not null,
  district text not null,
  hazard text not null check (hazard in ('flood', 'fire', 'stormSurge')),
  relative real not null check (relative >= 0 and relative <= 1),
  -- Which fit made it; 'sample' while the KDE runs on made-up records.
  model_version text not null,
  computed_at timestamptz not null default now(),
  primary key (barangay, hazard)
);
comment on table public.hazard_density is
  'KDE relative density per barangay and hazard (hotspots of past incidents). Not a forecast.';

alter table public.hazard_density enable row level security;

grant select on public.hazard_density to authenticated;

create policy "hazard density: dispatchers and admins" on public.hazard_density
  for select to authenticated
  using ((select private.is_dispatcher()));

alter publication supabase_realtime add table public.hazard_density;
