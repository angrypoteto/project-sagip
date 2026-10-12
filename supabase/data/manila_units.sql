-- Ten real responder stations in the City of Manila, loaded for the defense
-- (Joshua, 2026-10-12: "add only 10 for presentation purposes").
--
-- Source: OpenStreetMap (Overpass: amenity=fire_station and
-- emergency=ambulance_station inside Manila, plus the MDRRMD building),
-- read on 2026-10-12. Names, streets, and positions are OpenStreetMap's.
-- MDRRMD's own roster of units is not public: replace these with the
-- department's list when it is given.
--
-- What is NOT from the source and was assigned here: the call signs (the
-- system needs a short one), the unit type per station (one unit each),
-- and nothing else. Crew sizes are not known and are left empty. The
-- position is the station's, not a live GPS fix, so last_location_at is
-- empty. No supplies are loaded: a unit's crew reports them.
--
-- Safe to run again: existing rows are left as they are.

insert into public.response_unit
  (unit_id, call_sign, unit_type, agency, station, last_latitude, last_longitude, source)
values
  ('unit-mdr-delpan', 'MDR-DELPAN', 'rescueTeam', 'mdrrmd',
   'Manila DRRM Building, Delpan', 14.59884, 120.96576, 'OpenStreetMap, 2026-10-12'),
  ('unit-bfp-pandacan', 'BFP-PANDACAN', 'fireTruck', 'bfp',
   'Pandacan Fire Station, L. Certeza Street', 14.59200, 121.01193, 'OpenStreetMap, 2026-10-12'),
  ('unit-bfp-snlazaro', 'BFP-SNLAZARO', 'fireTruck', 'bfp',
   'San Lazaro Fire Station, Rizal Avenue', 14.61293, 120.98234, 'OpenStreetMap, 2026-10-12'),
  ('unit-bfp-intramur', 'BFP-INTRAMUR', 'fireTruck', 'bfp',
   'Intramuros Fire Station, Andres Soriano Avenue', 14.59220, 120.97218, 'OpenStreetMap, 2026-10-12'),
  ('unit-bfp-snicolas', 'BFP-SNICOLAS', 'fireTruck', 'bfp',
   'San Nicolas Fire Station, San Fernando Street', 14.59727, 120.97057, 'OpenStreetMap, 2026-10-12'),
  ('unit-bfp-paco', 'BFP-PACO', 'fireTruck', 'bfp',
   'Paco Fire Sub-station, San Marcelino Street', 14.58059, 120.98823, 'OpenStreetMap, 2026-10-12'),
  ('unit-bfp-tondo', 'BFP-TONDO', 'fireTruck', 'bfp',
   'Tondo Fire Station, Plaza Hernandez', 14.60762, 120.96656, 'OpenStreetMap, 2026-10-12'),
  ('unit-bfp-staana', 'BFP-STAANA', 'fireTruck', 'bfp',
   'Santa Ana Fire Station, Pedro Gil Street', 14.58013, 121.00813, 'OpenStreetMap, 2026-10-12'),
  ('unit-bfp-gagalang', 'BFP-GAGALANG', 'fireTruck', 'bfp',
   'Gagalangin Fire Station, Juan Luna Street', 14.62459, 120.97304, 'OpenStreetMap, 2026-10-12'),
  ('unit-ems-snlazaro', 'EMS-SNLAZARO', 'ambulance', 'ems',
   'Emergency Medical Services, San Lazaro', 14.61307, 120.98217, 'OpenStreetMap, 2026-10-12')
on conflict (unit_id) do nothing;
