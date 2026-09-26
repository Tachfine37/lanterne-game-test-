import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lanterne/main.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(375, 667),
    const Size(1440, 900),
    const Size(844, 390),
  ]) {
    testWidgets('Start, pause and resume at ${size.width} x ${size.height}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const LanternApp());
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Entrer dans le jardin'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Entrer dans le jardin'));
      await tester.tap(find.text('Entrer dans le jardin'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Entrer dans le jardin'), findsNothing);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(find.text('Reprendre le voyage'), findsOneWidget);
      await tester.ensureVisible(find.text('Reprendre le voyage'));
      await tester.tap(find.text('Reprendre le voyage'));
      await tester.pump();
      expect(find.text('Reprendre le voyage'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
