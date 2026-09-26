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
  testWidgets('Altar spends embers on a saved perk', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'lanterne.embers': 40});
    await tester.pumpWidget(const LanternApp());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.ensureVisible(find.text('Autel des braises  ·  40'));
    await tester.tap(find.text('Autel des braises  ·  40'));
    await tester.pump();
    expect(find.text('L’AUTEL DES BRAISES'), findsOneWidget);
    await tester.ensureVisible(find.text('30 ✦').first);
    await tester.tap(find.text('30 ✦').first);
    await tester.pump();
    expect(find.text('10 braises'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('lanterne.perk.vitality'), 1);
    expect(prefs.getInt('lanterne.embers'), 10);
    await tester.ensureVisible(find.text('Retour'));
    await tester.tap(find.text('Retour'));
    await tester.pump();
    expect(find.text('Entrer dans le jardin'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
