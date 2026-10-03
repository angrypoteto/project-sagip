import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_mobile/src/features/responder/voice_guide.dart';

void main() {
  test('a turn is said when it appears and again when it is near', () {
    final g = VoiceGuide();
    var line = g.update(
      atScene: false,
      turn: 'Turn right onto Lacson',
      meters: 420,
    );
    expect((line!.turn, line.meters), ('Turn right onto Lacson', 420));
    expect(
      g.update(atScene: false, turn: 'Turn right onto Lacson', meters: 300),
      isNull,
    );
    line = g.update(atScene: false, turn: 'Turn right onto Lacson', meters: 70);
    expect((line!.turn, line.meters), ('Turn right onto Lacson', null));
    expect(
      g.update(atScene: false, turn: 'Turn right onto Lacson', meters: 20),
      isNull,
    );
    // The next one, already close: said once, as now.
    line = g.update(atScene: false, turn: 'Turn left onto España', meters: 40);
    expect((line!.turn, line.meters), ('Turn left onto España', null));
    expect(
      g.update(atScene: false, turn: 'Turn left onto España', meters: 30),
      isNull,
    );
  });

  test('the arrival is said once; no turn says nothing', () {
    final g = VoiceGuide();
    expect(g.update(atScene: false), isNull);
    expect(g.update(atScene: true)!.isScene, isTrue);
    expect(g.update(atScene: true), isNull);
  });

  test('distances are said in round numbers', () {
    expect(spokenDistance(23).meters, 50);
    expect(spokenDistance(312).meters, 300);
    expect(spokenDistance(990).meters, 950);
    expect(spokenDistance(1260).kilometers, '1.3');
  });
}
