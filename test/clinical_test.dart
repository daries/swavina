import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavina/core/clinical.dart';
import 'package:swavina/core/theme.dart';
import 'package:swavina/screens/clinical_screen.dart';

ClinicalData sample() => ClinicalData(
      participant: {'code': 'INT-001', 'group_type': 'intervensi'},
      updatedAt: DateTime(2026, 10, 18),
      measurements: [
        ClinicalMeasurement({
          'timepoint': 'pre', 'measured_at': '2026-10-08', 'abi_left': 0.88, 'abi_right': 0.92,
          'ntss6_total': 5.99, 'dn4_total': 4, 'nrs': 4, 'skin_temp_left': 29.8, 'skin_temp_right': 32.4, 'lactate': 2.1,
        }),
        ClinicalMeasurement({
          'timepoint': 'post', 'measured_at': '2026-11-05', 'abi_left': 0.95, 'abi_right': 1.02,
          'ntss6_total': 1.0, 'nrs': 7, 'skin_temp_left': 31.5, 'skin_temp_right': 32.0, 'lactate': 1.8,
        }),
      ],
    );

void main() {
  test('Kategori ABI sesuai proposal', () {
    expect(abiCategory(0.85)!.label, 'Abnormal');
    expect(abiCategory(0.90)!.label, 'Abnormal');
    expect(abiCategory(0.95)!.label, 'Borderline');
    expect(abiCategory(1.10)!.label, 'Normal');
    expect(abiCategory(1.45)!.label, 'Arteri kaku');
    expect(abiCategory(null), isNull);
  });

  test('Baseline = pre-test, latest = pengukuran terakhir', () {
    final d = sample();
    expect(d.baseline!.timepoint, 'pre');
    expect(d.latest!.timepoint, 'post');
  });

  for (final width in [390.0, 320.0]) {
    testWidgets('Halaman Data Klinis tampil tanpa overflow (lebar $width)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: ClinicalScreen(initial: sample()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Vaskularisasi Kaki (ABI)'), findsOneWidget);
      expect(find.text('0,95'), findsWidgets);
      expect(find.text('Borderline'), findsOneWidget); // kiri 0,95
      expect(find.text('Normal'), findsOneWidget); // kanan 1,02
      expect(find.text('Perkembangan'), findsOneWidget);
      expect(find.text('Membaik'), findsWidgets); // ABI naik, NTSS-6 & laktat turun
      expect(find.text('Perlu perhatian'), findsOneWidget); // NRS 4 → 7
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Belum terdaftar sebagai responden', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      home: ClinicalScreen(
        initial: ClinicalData(participant: null, measurements: [], updatedAt: DateTime(2026)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Belum terdaftar sebagai responden'), findsOneWidget);
  });
}
