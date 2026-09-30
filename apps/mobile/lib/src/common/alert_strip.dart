import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../router.dart';

/// One line for the latest PAGASA conditions. Hidden when calm or when the
/// feed fails (plan R1: the strip hides silently).
class AlertStrip extends ConsumerWidget {
  const AlertStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final w = ref.watch(weatherProvider).value;
    if (w == null ||
        (w.signalLevel == 0 &&
            w.rainfallMmPerHour < 7.5 &&
            w.stormSurgeAdvisory == null)) {
      return const SizedBox.shrink();
    }
    final mm = w.rainfallMmPerHour.toStringAsFixed(
      w.rainfallMmPerHour % 1 == 0 ? 0 : 1,
    );
    return Material(
      color: p.warning.tint,
      borderRadius: BorderRadius.circular(SagipRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(SagipRadius.card),
        onTap: () => context.go(Routes.alerts),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SagipSpace.lg,
            vertical: SagipSpace.md,
          ),
          child: Row(
            children: [
              Icon(Symbols.thunderstorm_rounded, color: p.warning.text),
              const SizedBox(width: SagipSpace.md),
              Expanded(
                child: Text(
                  w.signalLevel > 0
                      ? l10n.alertStripSignal(w.signalLevel, mm)
                      : l10n.alertStripRain(mm),
                  style: text.bodyMedium!.copyWith(
                    color: p.warning.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Symbols.chevron_right_rounded, color: p.warning.text),
            ],
          ),
        ),
      ),
    );
  }
}
