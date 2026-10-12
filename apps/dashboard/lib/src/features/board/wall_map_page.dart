import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/screen.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';
import '../shell/new_sos_toast.dart';
import 'incident_map.dart';
import 'map_parts.dart';

/// The Command Board's map by itself (D2), for a second monitor or a wall
/// screen: no queue, no menu, larger markers, and a full screen button. It
/// shows the same live incidents and still announces a new SOS; deciding
/// and dispatching stay on the Command Board.
class WallMapPage extends ConsumerStatefulWidget {
  const WallMapPage({super.key});

  @override
  ConsumerState<WallMapPage> createState() => _WallMapPageState();
}

class _WallMapPageState extends ConsumerState<WallMapPage> {
  String? _selected;
  late final StreamSubscription<void> _fullScreen;

  @override
  void initState() {
    super.initState();
    // Esc leaves full screen without the button: keep its icon right.
    _fullScreen = fullScreenChanges.listen((_) {
      if (mounted) setState(() {});
    });
    // Demo only: the sample incidents move in this window too.
    ref.read(mockBackendProvider)?.startSimulation();
  }

  @override
  void dispose() {
    _fullScreen.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final incidents = ref.watch(activeIncidentsProvider).value ?? const [];
    final waiting = incidents.where((i) => i.assignedUnitId == null).length;
    final full = isFullScreen;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IncidentMap(
              wall: true,
              selectedId: _selected,
              // Tapping only marks the incident here; the drawer is on the
              // Command Board.
              onSelect: (id) =>
                  setState(() => _selected = id == _selected ? null : id),
            ),
          ),
          Positioned(
            left: SagipSpace.lg,
            top: SagipSpace.lg,
            child: Container(
              key: const ValueKey('wall-summary'),
              padding: const EdgeInsets.symmetric(
                horizontal: SagipSpace.lg,
                vertical: SagipSpace.md,
              ),
              decoration: floatingCard(p),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatClock(now, locale),
                    style: text.headlineSmall!.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: SagipSpace.xs),
                  Text(
                    l10n.wallSummary(incidents.length, waiting),
                    style: text.titleSmall,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: SagipSpace.lg,
            child: const Center(child: NewSosToast()),
          ),
          Positioned(
            right: SagipSpace.lg,
            // Beside the layers card, which keeps the corner.
            top: SagipSpace.lg,
            child: Padding(
              padding: const EdgeInsets.only(right: 200 + SagipSpace.sm),
              child: Container(
                decoration: floatingCard(p),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const ValueKey('wall-full-screen'),
                      tooltip: full
                          ? l10n.wallExitFullScreen
                          : l10n.wallFullScreen,
                      onPressed: () async {
                        await toggleFullScreen();
                        if (mounted) setState(() {});
                      },
                      icon: Icon(
                        full
                            ? Symbols.fullscreen_exit_rounded
                            : Symbols.fullscreen_rounded,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('wall-to-board'),
                      tooltip: l10n.wallToBoard,
                      onPressed: () => context.go(Routes.board),
                      icon: const Icon(Symbols.space_dashboard_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
