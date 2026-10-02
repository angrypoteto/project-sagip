// The short sound for a new SOS (D2). The web version plays two tones with
// the Web Audio API, so no sound file is needed; tests and other platforms
// get the stub, which counts the calls.
export 'chime_stub.dart' if (dart.library.js_interop) 'chime_web.dart';
