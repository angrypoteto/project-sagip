import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  late int sent;
  late int opened;

  Future<void> pump(WidgetTester tester, {bool active = false}) async {
    sent = 0;
    opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: SagipTheme.light(SagipDensity.mobile),
        home: Scaffold(
          body: Center(
            child: SosButton(
              phase: active ? SosButtonPhase.delivered : SosButtonPhase.ready,
              semanticLabel: 'Send SOS. Hold for 2 seconds.',
              onSend: () => sent++,
              onOpen: active ? () => opened++ : null,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a tap never sends', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(SosButton));
    await tester.pump(const Duration(seconds: 3));
    expect(sent, 0);
  });

  testWidgets('holding for 2 seconds sends once', (tester) async {
    await pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SosButton)),
    );
    await tester.pump(); // the hold animation starts timing on this frame
    await tester.pump(const Duration(milliseconds: 1000));
    expect(sent, 0);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(sent, 1);
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    expect(sent, 1);
  });

  testWidgets('letting go early cancels', (tester) async {
    await pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SosButton)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await gesture.up();
    await tester.pump(const Duration(seconds: 3));
    expect(sent, 0);
  });

  testWidgets('with an active SOS, a tap opens it instead of sending', (
    tester,
  ) async {
    await pump(tester, active: true);
    await tester.tap(find.byType(SosButton));
    await tester.pump();
    expect(opened, 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SosButton)),
    );
    await tester.pump(const Duration(seconds: 3));
    await gesture.up();
    await tester.pump();
    expect(sent, 0);
  });

  testWidgets('lifting the finger after a send does not also open', (
    tester,
  ) async {
    sent = 0;
    opened = 0;
    var active = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: SagipTheme.light(SagipDensity.mobile),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => SosButton(
                phase: active ? SosButtonPhase.sending : SosButtonPhase.ready,
                semanticLabel: 'Send SOS. Hold for 2 seconds.',
                // Sending makes the button active while the finger is down,
                // as it does on the Home screen.
                onSend: () => setState(() {
                  sent++;
                  active = true;
                }),
                onOpen: active ? () => opened++ : null,
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SosButton)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2100));
    await gesture.up();
    await tester.pump();
    expect(sent, 1);
    expect(opened, 0);
    // Stop the sending pulse before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('screen readers get a label', (tester) async {
    await pump(tester);
    expect(
      find.bySemanticsLabel('Send SOS. Hold for 2 seconds.'),
      findsOneWidget,
    );
  });
}
