import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';

/// A crew member's duty (2026-11-01): On duty, Not reporting (on duty but
/// the phone has been quiet longer than [quiet]), or Off duty. Always icon
/// and words, never color alone.
class DutyChip extends StatelessWidget {
  const DutyChip({
    super.key,
    required this.member,
    required this.now,
    required this.quiet,
  });

  final CrewMember member;
  final DateTime now;
  final Duration quiet;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final (label, tone, icon) = !member.onDuty
        ? (l10n.dutyOff, p.neutral, Symbols.bedtime_rounded)
        : member.isQuiet(now, quiet)
        ? (l10n.dutyQuiet, p.warning, Symbols.signal_disconnected_rounded)
        : (l10n.dutyOn, p.success, Symbols.how_to_reg_rounded);
    return SagipChip(label: label, tone: tone, icon: icon);
  }
}

/// "Since 7:02 AM · seen 1 min ago"; for someone off duty, only when their
/// phone was last seen.
String dutyDetail(
  AppLocalizations l10n,
  CrewMember m,
  DateTime now,
  String locale,
) => [
  if (m.onDuty && m.dutySince != null)
    l10n.dutySince(formatTime(m.dutySince!, locale)),
  if (m.lastSeenAt != null)
    l10n.dutySeen(l10n.ago(m.lastSeenAt!, now))
  else if (m.onDuty)
    l10n.dutyNeverSeen,
].join(' · ');
