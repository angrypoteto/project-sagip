import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

/// F2 Incoming assignment: a full-screen alert with sound and vibration.
/// "Accept and start" sets En route and starts saving the map for offline
/// use. Declining is not in the thesis (plan Q10).
class IncomingPage extends ConsumerStatefulWidget {
  const IncomingPage({super.key});

  @override
  ConsumerState<IncomingPage> createState() => _IncomingPageState();
}

class _IncomingPageState extends ConsumerState<IncomingPage> {
  Timer? _alert;
  var _pulses = 0;
  var _accepting = false;

  @override
  void initState() {
    super.initState();
    // Nothing may cover "Accept and start": clear leftover messages, such as
    // a status notice from F1, as the alert opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    });
    // Three alert pulses: the phone's alert sound plus a strong vibration.
    // A custom siren sound comes with the push notification work (FCM).
    _pulse();
    _alert = Timer.periodic(const Duration(seconds: 2), (t) {
      if (++_pulses >= 2) t.cancel();
      _pulse();
    });
  }

  void _pulse() {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.vibrate();
  }

  @override
  void dispose() {
    _alert?.cancel();
    super.dispose();
  }

  Future<void> _accept(Assignment offer) async {
    setState(() => _accepting = true);
    await ref.read(responderRepositoryProvider).accept(offer.incidentId);
    if (mounted) context.pushReplacement(Routes.assignment);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final state = ref.watch(responderProvider).value;
    final offer = state?.offer;

    if (offer == null) {
      // Already accepted or withdrawn: nothing to show.
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Symbols.task_alt_rounded,
          title: l10n.noAssignmentTitle,
        ),
      );
    }
    final estimate = routeEstimate(ref, state, offer);

    return Scaffold(
      // Tints are translucent; blend onto the canvas so the whole screen is
      // an opaque light (or dark) red, not the black window behind it.
      backgroundColor: Color.alphaBlend(p.critical.tint, p.canvas),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SagipSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: SagipSpace.xl),
              Row(
                children: [
                  Icon(
                    Symbols.notifications_active_rounded,
                    color: p.critical.text,
                    size: 28,
                    fill: 1,
                  ),
                  const SizedBox(width: SagipSpace.sm),
                  Expanded(
                    child: Text(
                      l10n.newAssignment,
                      style: text.titleMedium!.copyWith(color: p.critical.text),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SagipSpace.x3),
              Text(
                l10n.typeOrEmergency(offer.type),
                style: text.displaySmall!.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: SagipSpace.sm),
              Text(offer.place, style: text.titleLarge),
              if (offer.address != null)
                Text(offer.address!, style: text.bodyLarge),
              const SizedBox(height: SagipSpace.lg),
              if (estimate != null)
                Text(
                  l10n.distanceEta(
                    formatDistance(estimate.meters),
                    estimate.minutes,
                  ),
                  style: text.titleMedium!.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              if (offer.vulnerable.isNotEmpty) ...[
                const SizedBox(height: SagipSpace.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SagipChip(
                    label: l10n.vulnerableTypes(
                      offer.vulnerable.map(l10n.vulnerability).join(', '),
                    ),
                    tone: p.warning,
                    icon: Symbols.accessible_rounded,
                    dense: false,
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: _accepting ? null : () => _accept(offer),
                  icon: const Icon(Symbols.play_arrow_rounded),
                  label: Text(l10n.acceptAndStart),
                ),
              ),
              const SizedBox(height: SagipSpace.md),
              OutlinedButton(
                onPressed: () => context.push(Routes.assignment),
                child: Text(l10n.viewDetails),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
