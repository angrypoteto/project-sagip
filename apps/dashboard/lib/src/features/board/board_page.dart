import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../router.dart';
import 'incident_drawer.dart';
import 'incident_map.dart';
import 'incident_table.dart';
import 'queue_panel.dart';

/// D2/D3/D4: Triage Queue on the left, map or list in the center, and the
/// incident drawer sliding over it from the right.
///
/// The open incident and the view live in the URL (?incident=…&view=list),
/// so a dispatcher can share a link or use the browser back button.
class BoardPage extends ConsumerWidget {
  const BoardPage({super.key, this.selectedId, this.listView = false});

  final String? selectedId;
  final bool listView;

  void _select(BuildContext context, String? id) {
    context.go(
      id == null
          ? Uri(
              path: Routes.board,
              queryParameters: listView ? {'view': 'list'} : null,
            ).toString()
          : Routes.incident(id, list: listView),
    );
  }

  void _setView(BuildContext context, bool list) {
    context.go(
      Uri(
        path: Routes.board,
        queryParameters: {'incident': ?selectedId, if (list) 'view': 'list'},
      ).toString(),
    );
  }

  /// Arrow keys move through the queue, Esc closes the drawer (design skill).
  KeyEventResult _onKey(BuildContext context, WidgetRef ref, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final queue = ref.read(visibleQueueProvider);
    if (event.logicalKey == LogicalKeyboardKey.escape && selectedId != null) {
      _select(context, null);
      return KeyEventResult.handled;
    }
    final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if ((!down && !up) || queue.isEmpty) return KeyEventResult.ignored;
    final index = queue.indexWhere((i) => i.id == selectedId);
    final next = index < 0
        ? 0
        : (index + (down ? 1 : -1)).clamp(0, queue.length - 1);
    _select(context, queue[next].id);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = SagipPalette.of(context);
    final drawerOpen = selectedId != null;
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) => _onKey(context, ref, event),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 380,
            child: QueuePanel(
              selectedId: selectedId,
              onSelect: (id) => _select(context, id),
            ),
          ),
          VerticalDivider(width: 1, color: p.hairline),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: listView
                      ? IncidentTable(
                          selectedId: selectedId,
                          onSelect: (id) => _select(context, id),
                        )
                      : IncidentMap(
                          selectedId: selectedId,
                          onSelect: (id) => _select(context, id),
                        ),
                ),
                Positioned(
                  left: SagipSpace.lg,
                  top: SagipSpace.lg,
                  child: ViewToggle(
                    listView: listView,
                    onChanged: (list) => _setView(context, list),
                  ),
                ),
                AnimatedPositioned(
                  duration: SagipMotion.base,
                  curve: drawerOpen ? SagipMotion.enter : SagipMotion.exit,
                  top: 0,
                  bottom: 0,
                  right: drawerOpen ? 0 : -IncidentDrawer.width,
                  width: IncidentDrawer.width,
                  child: drawerOpen
                      ? IncidentDrawer(
                          key: ValueKey(selectedId),
                          incidentId: selectedId!,
                          onClose: () => _select(context, null),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
