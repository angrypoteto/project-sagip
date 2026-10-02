// The browser features the resident web form uses: geolocation, a draft
// store (localStorage), the online state, and opening a link. The web
// version uses package:web; tests and other platforms get the stubs.
export 'browser_stub.dart' if (dart.library.js_interop) 'browser_web.dart';
export 'browser_types.dart';
