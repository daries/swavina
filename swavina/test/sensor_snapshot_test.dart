import 'package:flutter_test/flutter_test.dart';
import 'package:swavina/core/device_service.dart';

void main() {
  test('SensorSnapshot membaca JSON /status ESP8266', () {
    final s = SensorSnapshot.fromJson({
      'simulated': true,
      'left': {'temp': 36.4, 'vib': 44.8},
      'right': {'temp': 35, 'vib': 43.1},
    })!;
    expect(s.simulated, isTrue);
    expect(s.left.temp, 36.4);
    expect(s.left.vib, 44.8);
    expect(s.right.temp, 35.0);
    expect(s.right.vib, 43.1);
  });

  test('Nilai sensor yang hilang menjadi null', () {
    final s = SensorSnapshot.fromJson({'left': {'temp': 33.0}, 'right': null})!;
    expect(s.simulated, isFalse);
    expect(s.left.vib, isNull);
    expect(s.right.temp, isNull);
    expect(SensorSnapshot.fromJson(null), isNull);
  });
}
