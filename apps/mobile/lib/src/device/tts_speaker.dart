import 'package:flutter_tts/flutter_tts.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Spoken directions through Android's text-to-speech (works offline with
/// the phone's installed voice). Fails quietly: the card still shows every
/// instruction.
class TtsSpeaker implements Speaker {
  TtsSpeaker();

  final _tts = FlutterTts();
  Future<void>? _ready;

  Future<void> _setUp() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.awaitSpeakCompletion(false);
  }

  @override
  Future<void> say(String text) async {
    try {
      await (_ready ??= _setUp());
      await _tts.stop();
      await _tts.speak(text);
    } on Object {
      _ready = null;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object {
      // Nothing to stop.
    }
  }
}
