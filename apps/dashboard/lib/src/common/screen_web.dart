import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Not used on the web; kept so both versions have the same names.
final openedWindows = <String>[];

/// Opens [route] (for example `/wall`) in a window of its own, which can
/// be moved to another monitor. The window keeps one name, so pressing
/// the button twice brings the same window back instead of making more.
void openInNewWindow(String route) {
  final here = web.window.location;
  web.window.open(
    '${here.origin}${here.pathname}#$route',
    'sagip-wall',
    'popup,width=1280,height=800',
  );
}

bool get isFullScreen => web.document.fullscreenElement != null;

/// Fills the screen with the page, or goes back to the window. Browsers
/// allow this only from a click, which is where it is called from.
Future<void> toggleFullScreen() async {
  try {
    if (isFullScreen) {
      await web.document.exitFullscreen().toDart;
    } else {
      await web.document.documentElement!.requestFullscreen().toDart;
    }
  } catch (_) {
    // Refused by the browser: the window stays as it is.
  }
}

/// Emits whenever full screen starts or ends (also with Esc).
Stream<void> get fullScreenChanges {
  final controller = StreamController<void>.broadcast();
  final listener = ((web.Event _) => controller.add(null)).toJS;
  controller.onListen = () =>
      web.document.addEventListener('fullscreenchange', listener);
  controller.onCancel = () =>
      web.document.removeEventListener('fullscreenchange', listener);
  return controller.stream;
}
