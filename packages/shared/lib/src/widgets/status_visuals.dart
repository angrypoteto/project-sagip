import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../models/enums.dart';
import '../models/offline.dart';
import '../theme/sagip_palette.dart';

/// How a chip is drawn.
enum ChipLook {
  /// Tinted background with full-strength text.
  tint,

  /// Outline only (Assigned).
  outline,

  /// Dashed outline with muted text (Unverified).
  dashed,
}

/// Color, icon, and look for a status. Text comes from the app's l10n files.
@immutable
class StatusVisual {
  const StatusVisual(this.tone, this.icon, [this.look = ChipLook.tint]);

  final SagipTone tone;
  final IconData? icon;
  final ChipLook look;
}

/// Status mapping from the design skill: always color, icon, and label.
StatusVisual incidentStatusVisual(
  IncidentStatus status,
  SagipPalette p,
) => switch (status) {
  IncidentStatus.pendingVerification => StatusVisual(
    p.warning,
    Symbols.hourglass_top_rounded,
  ),
  IncidentStatus.unverified => StatusVisual(p.neutral, null, ChipLook.dashed),
  IncidentStatus.confirmed => StatusVisual(p.critical, Symbols.warning_rounded),
  IncidentStatus.assigned => StatusVisual(
    p.info,
    Symbols.assignment_ind_rounded,
    ChipLook.outline,
  ),
  IncidentStatus.enRoute => StatusVisual(p.info, Symbols.navigation_rounded),
  IncidentStatus.onScene => StatusVisual(
    p.onScene,
    Symbols.location_on_rounded,
  ),
  IncidentStatus.resolved => StatusVisual(
    p.success,
    Symbols.check_circle_rounded,
  ),
};

StatusVisual unitStatusVisual(
  UnitStatus status,
  SagipPalette p,
) => switch (status) {
  UnitStatus.available => StatusVisual(p.success, Symbols.check_circle_rounded),
  UnitStatus.enRoute => StatusVisual(p.info, Symbols.navigation_rounded),
  UnitStatus.onScene => StatusVisual(p.onScene, Symbols.location_on_rounded),
};

Color severityColor(Severity severity, SagipPalette p) => switch (severity) {
  Severity.critical => p.critical.fill,
  Severity.high => p.warning.fill,
  Severity.normal => p.neutral.fill,
};

IconData incidentTypeIcon(IncidentType? type) => switch (type) {
  IncidentType.flood => Symbols.flood_rounded,
  IncidentType.fire => Symbols.local_fire_department_rounded,
  IncidentType.medical => Symbols.medical_services_rounded,
  IncidentType.structural => Symbols.domain_disabled_rounded,
  null => Symbols.sos_rounded,
};

IconData unitTypeIcon(UnitType type) => switch (type) {
  UnitType.ambulance => Symbols.ambulance_rounded,
  UnitType.rescueBoat => Symbols.directions_boat_rounded,
  UnitType.rescueTeam => Symbols.groups_rounded,
};

IconData channelIcon(ReportChannel channel) => switch (channel) {
  ReportChannel.app => Symbols.smartphone_rounded,
  ReportChannel.sms => Symbols.sms_rounded,
  ReportChannel.bleRelay => Symbols.bluetooth_rounded,
  ReportChannel.webForm => Symbols.language_rounded,
};

IconData vulnerabilityIcon(VulnerabilityType type) => switch (type) {
  VulnerabilityType.seniorCitizen => Symbols.elderly_rounded,
  VulnerabilityType.pwd => Symbols.accessible_rounded,
  VulnerabilityType.pregnant => Symbols.pregnant_woman_rounded,
  VulnerabilityType.other => Symbols.favorite_rounded,
};

/// Delivery badges for records made on the phone (plan 7.6).
StatusVisual deliveryVisual(DeliveryState state, SagipPalette p) =>
    switch (state) {
      DeliveryState.savedOnPhone => StatusVisual(
        p.warning,
        Symbols.smartphone_rounded,
      ),
      DeliveryState.sending => StatusVisual(p.info, Symbols.upload_rounded),
      DeliveryState.sentBySms => StatusVisual(p.info, Symbols.sms_rounded),
      DeliveryState.relaying => StatusVisual(
        p.onScene,
        Symbols.bluetooth_searching_rounded,
      ),
      DeliveryState.delivered => StatusVisual(
        p.success,
        Symbols.check_circle_rounded,
      ),
      DeliveryState.rejected => StatusVisual(p.critical, Symbols.block_rounded),
    };
