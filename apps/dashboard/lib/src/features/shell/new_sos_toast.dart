import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/chime.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

/// Watches the queue and, when a new SOS arrives, pops a toast and plays
/// a short sound, on any page.
class NewSosToast extends ConsumerStatefulWidget {
  const NewSosToast({super.key});

  @override
  ConsumerState<NewSosToast> createState() => _NewSosToastState();
}

class _NewSosToastState extends ConsumerState<NewSosToast> {
  Incident? _showing;
  Timer? _hideTimer;

  static const _visibleFor = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    ref.listenManual(activeIncidentsProvider, (previous, next) {
      final before = previous?.value;
      final after = next.value;
      if (before == null || after == null) return; // First load: no toast.
      final known = {for (final i in before) i.id};
      final fresh = after.where(
        (i) => i.origin == IncidentOrigin.sos && !known.contains(i.id),
      );
      if (fresh.isNotEmpty) _show(fresh.last);
    });
  }

  void _show(Incident incident) {
    if (ref.read(sosSoundProvider)) playNewSosChime();
    _hideTimer?.cancel();
    setState(() => _showing = incident);
    _hideTimer = Timer(_visibleFor, _hide);
  }

  void _hide() {
    _hideTimer?.cancel();
    if (mounted) setState(() => _showing = null);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incident = _showing;
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider).value ?? DateTime.now();

    return AnimatedSwitcher(
      duration: SagipMotion.emphasis,
      switchInCurve: SagipMotion.enter,
      switchOutCurve: SagipMotion.exit,
      child: incident == null
          ? const SizedBox.shrink()
          : Semantics(
              key: ValueKey(incident.id),
              liveRegion: true,
              child: Container(
                width: 400,
                padding: const EdgeInsets.fromLTRB(
                  SagipSpace.lg,
                  SagipSpace.md,
                  SagipSpace.sm,
                  SagipSpace.md,
                ),
                decoration: BoxDecoration(
                  color: p.panel,
                  borderRadius: BorderRadius.circular(SagipRadius.card),
                  border: Border.all(color: p.hairline),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 32,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: p.critical.fill,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: SagipSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.newSosTitle, style: text.titleSmall),
                          Text(
                            l10n.newSosBody(
                              incident.place,
                              l10n.ago(incident.receivedAt, now),
                            ),
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _hide();
                        context.go(Routes.incident(incident.id));
                      },
                      child: Text(l10n.open),
                    ),
                    IconButton(
                      tooltip: l10n.dismiss,
                      onPressed: _hide,
                      icon: const Icon(Symbols.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
