/// Shared code for the S.A.G.I.P. mobile app and web dashboard: design
/// tokens and theme, domain models, repository interfaces with mock and
/// Supabase implementations, algorithms, and shared widgets.
library;

export 'src/algorithms/dbscan.dart';
export 'src/algorithms/priority.dart';
export 'src/algorithms/unit_suggester.dart';
export 'src/data/manila_barangays.dart';
export 'src/format.dart';
export 'src/mock/mock_backend.dart';
export 'src/mock/mock_mobile_backend.dart';
export 'src/mock/mock_mobile_repositories.dart';
export 'src/mock/mock_repositories.dart';
export 'src/mock/mock_seed.dart' show MockSeed;
export 'src/models/account.dart';
export 'src/models/alerts.dart';
export 'src/models/assignment.dart';
export 'src/models/crowd_report.dart';
export 'src/models/enums.dart';
export 'src/models/geo_point.dart';
export 'src/models/hazard_report.dart';
export 'src/models/incident.dart';
export 'src/models/offline.dart';
export 'src/models/people.dart';
export 'src/models/records.dart';
export 'src/models/response_unit.dart';
export 'src/models/sos.dart';
export 'src/repositories/repositories.dart';
export 'src/supabase/supabase_repositories.dart';
export 'src/theme/sagip_colors.dart';
export 'src/theme/sagip_palette.dart';
export 'src/theme/sagip_theme.dart';
export 'src/theme/sagip_tokens.dart';
export 'src/widgets/offline_widgets.dart';
export 'src/widgets/responder_widgets.dart';
export 'src/widgets/sagip_chip.dart';
export 'src/widgets/sagip_map.dart';
export 'src/widgets/sos_button.dart';
export 'src/widgets/state_views.dart';
export 'src/widgets/status_visuals.dart';
