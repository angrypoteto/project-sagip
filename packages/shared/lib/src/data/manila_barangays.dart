import '../models/account.dart';

/// A SAMPLE of Manila's barangays, only the ones the demo data uses.
///
/// The app needs all 897 with their districts, bundled so the picker works
/// offline (plan S4, R5). The Data role supplies that list; replace this
/// constant with it (or load it from an asset) when it arrives.
const sampleManilaBarangays = <Barangay>[
  Barangay('Barangay 105', 'Tondo'),
  Barangay('Barangay 128', 'Tondo'),
  Barangay('Barangay 287', 'Binondo'),
  Barangay('Barangay 306', 'Quiapo'),
  Barangay('Barangay 412', 'Sampaloc'),
  Barangay('Barangay 461', 'Sampaloc'),
  Barangay('Barangay 490', 'Sampaloc'),
  Barangay('Barangay 560', 'Sampaloc'),
  Barangay('Barangay 649', 'Port Area'),
  Barangay('Barangay 700', 'Malate'),
];
