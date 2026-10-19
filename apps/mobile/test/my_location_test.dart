import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_mobile/src/common/map_markers.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// The "your location" marker points where the phone faces (2026-10-19).
void main() {
  Future<void> pump(WidgetTester tester, double? heading) => tester.pumpWidget(
    MaterialApp(
      theme: SagipTheme.light(SagipDensity.mobile),
      home: Center(child: MyLocationMarker(heading: heading)),
    ),
  );

  testWidgets('with a compass: an arrow turned to the heading', (tester) async {
    await pump(tester, 90);
    final arrow = find.byIcon(Symbols.navigation_rounded);
    expect(arrow, findsOneWidget);
    final turn = tester.widget<Transform>(
      find.ancestor(of: arrow, matching: find.byType(Transform)).first,
    );
    // 90 degrees: pointing east.
    expect(
      turn.transform.getRotation().entry(0, 1),
      closeTo(-math.sin(math.pi / 2), 1e-9),
    );
  });

  testWidgets('without one: still the dot that marks you', (tester) async {
    await pump(tester, null);
    expect(find.byIcon(Symbols.navigation_rounded), findsNothing);
    expect(find.byType(MyLocationMarker), findsOneWidget);
  });
}
