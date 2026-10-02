import 'dart:async';
import 'dart:js_interop';

import 'package:sagip_shared/sagip_shared.dart';
import 'package:web/web.dart' as web;

import 'browser_types.dart';

class _WebLocation implements BrowserLocation {
  const _WebLocation();

  @override
  Future<({GeoPoint point, double accuracyMeters})> current() {
    final done = Completer<({GeoPoint point, double accuracyMeters})>();
    void fail(BrowserLocationFailure reason) {
      if (!done.isCompleted) {
        done.completeError(BrowserLocationException(reason));
      }
    }

    try {
      web.window.navigator.geolocation.getCurrentPosition(
        ((web.GeolocationPosition p) {
          if (done.isCompleted) return;
          done.complete((
            point: GeoPoint(p.coords.latitude, p.coords.longitude),
            accuracyMeters: p.coords.accuracy,
          ));
        }).toJS,
        ((web.GeolocationPositionError e) {
          fail(
            e.code == web.GeolocationPositionError.PERMISSION_DENIED
                ? BrowserLocationFailure.denied
                : BrowserLocationFailure.unavailable,
          );
        }).toJS,
        web.PositionOptions(
          enableHighAccuracy: true,
          timeout: 15000,
          maximumAge: 30000,
        ),
      );
    } on Object {
      // No geolocation at all (an old browser, or a page not on HTTPS).
      fail(BrowserLocationFailure.unavailable);
    }
    return done.future;
  }
}

/// localStorage. Private windows and strict settings can refuse it; the
/// draft then lives only as long as the page.
class _WebDraftStore implements DraftStore {
  final _fallback = <String, String>{};

  @override
  String? read(String key) {
    try {
      return web.window.localStorage.getItem(key) ?? _fallback[key];
    } on Object {
      return _fallback[key];
    }
  }

  @override
  void write(String key, String? value) {
    if (value == null) {
      _fallback.remove(key);
    } else {
      _fallback[key] = value;
    }
    try {
      if (value == null) {
        web.window.localStorage.removeItem(key);
      } else {
        web.window.localStorage.setItem(key, value);
      }
    } on Object {
      // Kept in memory only.
    }
  }
}

class _WebConnection implements BrowserConnection {
  const _WebConnection();

  @override
  Stream<bool> watch() {
    late final StreamController<bool> controller;
    final onOnline = ((web.Event _) => controller.add(true)).toJS;
    final onOffline = ((web.Event _) => controller.add(false)).toJS;
    controller = StreamController<bool>(
      onListen: () {
        controller.add(web.window.navigator.onLine);
        web.window.addEventListener('online', onOnline);
        web.window.addEventListener('offline', onOffline);
      },
      onCancel: () {
        web.window.removeEventListener('online', onOnline);
        web.window.removeEventListener('offline', onOffline);
      },
    );
    return controller.stream;
  }
}

BrowserLocation createBrowserLocation() => const _WebLocation();
DraftStore createDraftStore() => _WebDraftStore();
BrowserConnection createBrowserConnection() => const _WebConnection();

/// Not used on the web; kept so both versions have the same names.
String? lastOpenedLink;

void openLink(String url) {
  lastOpenedLink = url;
  web.window.open(url, '_blank', 'noopener');
}
