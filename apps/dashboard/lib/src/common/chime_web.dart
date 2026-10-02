import 'package:web/web.dart' as web;

/// Not used on the web; kept so both versions have the same names.
int chimesPlayed = 0;

web.AudioContext? _audio;

/// Two short rising tones. Browsers only allow sound after the person has
/// clicked somewhere on the page; signing in is that click.
void playNewSosChime() {
  try {
    final audio = _audio ??= web.AudioContext();
    if (audio.state == 'suspended') audio.resume();
    void tone(double hertz, double at) {
      final oscillator = audio.createOscillator();
      final gain = audio.createGain();
      oscillator.frequency.value = hertz;
      final start = audio.currentTime + at;
      // A soft start and end, so the tone does not click.
      gain.gain.setValueAtTime(0, start);
      gain.gain.linearRampToValueAtTime(0.18, start + 0.02);
      gain.gain.linearRampToValueAtTime(0, start + 0.2);
      oscillator.connect(gain);
      gain.connect(audio.destination);
      oscillator.start(start);
      oscillator.stop(start + 0.22);
    }

    tone(880, 0);
    tone(1175, 0.24);
  } catch (_) {
    // No sound is better than a broken board.
  }
}
