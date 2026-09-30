// Saves a text file in the browser (A4 CSV export). The web version uses
// package:web; tests and other platforms get the stub, which records the
// last file so tests can check it.
export 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';
