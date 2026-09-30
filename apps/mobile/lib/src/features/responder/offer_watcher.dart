import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../providers.dart';
import '../../router.dart';

/// Opens F2 (full screen, with sound and vibration) whenever a new
/// assignment is offered, whatever screen the responder is on.
class OfferWatcher extends ConsumerStatefulWidget {
  const OfferWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<OfferWatcher> createState() => _OfferWatcherState();
}

class _OfferWatcherState extends ConsumerState<OfferWatcher> {
  String? _shown;

  @override
  Widget build(BuildContext context) {
    ref.listen(responderProvider, (_, next) {
      final offer = next.value?.offer;
      if (offer == null) {
        _shown = null;
        return;
      }
      if (offer.incidentId == _shown) return;
      _shown = offer.incidentId;
      context.push(Routes.incoming);
    });
    return widget.child;
  }
}
