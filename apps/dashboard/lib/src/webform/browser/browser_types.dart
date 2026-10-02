import 'package:sagip_shared/sagip_shared.dart';

// What the resident web form needs from the browser. The web versions use
// package:web; tests and other platforms get the stubs in browser_stub.dart.

enum BrowserLocationFailure {
  /// The resident (or the browser's settings) refused to share it.
  denied,

  /// The browser could not find the position, or took too long.
  unavailable,
}

class BrowserLocationException implements Exception {
  const BrowserLocationException(this.reason);

  final BrowserLocationFailure reason;

  @override
  String toString() => 'BrowserLocationException($reason)';
}

/// The browser's geolocation (W2). Asking shows the browser's own
/// permission prompt, so the form only asks when the resident presses the
/// button.
abstract interface class BrowserLocation {
  /// Throws [BrowserLocationException].
  Future<({GeoPoint point, double accuracyMeters})> current();
}

/// A small text store that survives a reload (the browser's localStorage).
/// W2 keeps the report draft here.
abstract interface class DraftStore {
  String? read(String key);

  /// Null removes the value.
  void write(String key, String? value);
}

/// Whether the browser thinks it is online.
abstract interface class BrowserConnection {
  /// Emits the current state on listen, then every change.
  Stream<bool> watch();
}
