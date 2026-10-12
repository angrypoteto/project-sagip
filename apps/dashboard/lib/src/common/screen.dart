// A second browser window and full screen, for the wall map (D2 on another
// monitor). The web version uses package:web; tests and other platforms
// get the stub, which records the calls.
export 'screen_stub.dart' if (dart.library.js_interop) 'screen_web.dart';
