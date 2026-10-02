import 'browser_types.dart';

// Off the web (widget tests): no geolocation, a draft kept in memory, and
// always online. Tests override the providers with their own fakes.

class _NoLocation implements BrowserLocation {
  const _NoLocation();

  @override
  Future<Never> current() =>
      throw const BrowserLocationException(BrowserLocationFailure.unavailable);
}

/// Keeps values for as long as the object lives.
class MemoryDraftStore implements DraftStore {
  final _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String? value) {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}

class _AlwaysOnline implements BrowserConnection {
  const _AlwaysOnline();

  @override
  Stream<bool> watch() => Stream.value(true);
}

BrowserLocation createBrowserLocation() => const _NoLocation();
DraftStore createDraftStore() => MemoryDraftStore();
BrowserConnection createBrowserConnection() => const _AlwaysOnline();

/// The last link "opened" off the web (widget tests read it).
String? lastOpenedLink;

void openLink(String url) => lastOpenedLink = url;
