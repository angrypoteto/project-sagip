import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../models/offline.dart';
import '../theme/sagip_palette.dart';
import '../theme/sagip_tokens.dart';
import 'sagip_chip.dart';
import 'status_visuals.dart';

/// The slim bar at the top of every mobile screen when the phone is offline
/// or has just reconnected (plan 7.6). Calm, not an alarm. Text comes from
/// the app's l10n files, for example "Offline · 2 reports saved on your
/// phone". Tapping opens the offline queue.
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({
    super.key,
    required this.message,
    required this.icon,
    this.tone,
    this.onTap,
  });

  final String message;
  final IconData icon;

  /// Null for the neutral offline look; a tone such as `success` for
  /// "Back online".
  final SagipTone? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final fg = tone?.text ?? p.textPrimary;
    return Material(
      color: tone?.tint ?? p.panelRaised,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SagipSpace.xl,
              vertical: SagipSpace.sm,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: SagipSpace.md),
                Expanded(
                  child: Text(
                    message,
                    style: text.bodyMedium!.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(Symbols.chevron_right_rounded, size: 20, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How far a queued record has got: color, icon, and text (plan 7.6).
class DeliveryBadge extends StatelessWidget {
  const DeliveryBadge({
    super.key,
    required this.state,
    required this.label,
    this.dense = true,
  });

  final DeliveryState state;

  /// From the app's l10n files, for example "Saved on phone".
  final String label;
  final bool dense;

  @override
  Widget build(BuildContext context) => SagipChip.status(
    label: label,
    visual: deliveryVisual(state, SagipPalette.of(context)),
    dense: dense,
  );
}
