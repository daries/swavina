import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'device_service.dart';

/// Perangkat tiruan untuk demo tanpa ESP32/ESP8266: suhu kedua kaki naik
/// bertahap menuju target, getaran berfluktuasi di sekitar target.
class SimDevice extends ChangeNotifier {
  SimDevice._();
  static final SimDevice instance = SimDevice._();

  static const _skinTemp = 31.0; // suhu kulit awal (°C)

  final _rand = Random();
  Timer? _timer;
  bool _connected = false;
  String? _status;
  SensorSnapshot? _sensors;
  int _targetTemp = 0, _targetVib = 0, _elapsed = 0, _total = 0;
  double _left = _skinTemp, _right = _skinTemp - 0.4;

  bool get isConnected => _connected;
  String? get status => _status;
  SensorSnapshot? get sensors => _sensors;

  void connect() {
    _connected = true;
    _status = 'Siap';
    notifyListeners();
  }

  void disconnect() {
    _timer?.cancel();
    _timer = null;
    _connected = false;
    _status = null;
    _sensors = null;
    notifyListeners();
  }

  Future<void> startTherapy(int temp, int vib, int dur) async {
    _targetTemp = temp;
    _targetVib = vib;
    _total = dur * 60;
    _elapsed = 0;
    _left = _skinTemp;
    _right = _skinTemp - 0.4;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _tick();
  }

  Future<void> stopTherapy() async {
    _timer?.cancel();
    _timer = null;
    _status = 'Selesai';
    _sensors = null;
    notifyListeners();
  }

  double _noise(double amp) => (_rand.nextDouble() * 2 - 1) * amp;

  void _tick() {
    // Mendekati target ~8% per detik (stabil dalam ±1 menit), kanan sedikit lebih lambat.
    _left += (_targetTemp - _left) * 0.08 + _noise(0.05);
    _right += (_targetTemp - 0.2 - _right) * 0.07 + _noise(0.05);
    _sensors = SensorSnapshot(
      left: FootReading(temp: _left, vib: _targetVib + _noise(1.5)),
      right: FootReading(temp: _right, vib: _targetVib + _noise(1.5)),
      simulated: true,
      receivedAt: DateTime.now(),
    );
    final left = (_total - _elapsed).clamp(0, _total);
    _status = 'Berjalan ${(left ~/ 60).toString().padLeft(2, '0')}:${(left % 60).toString().padLeft(2, '0')}';
    _elapsed++;
    notifyListeners();
  }
}
