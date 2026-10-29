import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavina/main.dart';

void main() {
  testWidgets('Belum login -> tampil halaman Login', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SwavinaApp());
    await tester.pumpAndSettle();
    expect(find.text('Masuk ke Swavina'), findsOneWidget);
  });
}
