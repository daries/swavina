import 'package:flutter/foundation.dart';

import 'ble_service.dart';
import 'sim_device.dart';
import 'wifi_service.dart';

/// Error perangkat (BLE maupun WiFi) yang siap ditampilkan ke pengguna.
class DeviceException implements Exception {
  DeviceException(this.title, this.message);
  final String title;
  final String message;

  @override
  String toString() => '$title: $message';
}

enum DeviceTransport { bluetooth, wifi, simulation }

/// Pembacaan sensor satu kaki (null jika sensor tidak mengirim nilai).
class FootReading {
  const FootReading({this.temp, this.vib});
  final double? temp; // °C
  final double? vib; // Hz

  static FootReading fromJson(dynamic j) => j is Map
      ? FootReading(temp: (j['temp'] as num?)?.toDouble(), vib: (j['vib'] as num?)?.toDouble())
      : const FootReading();
}

/// Data sensor realtime kaki kiri & kanan dari perangkat.
class SensorSnapshot {
  const SensorSnapshot({
    required this.left,
    required this.right,
    required this.receivedAt,
    this.simulated = false,
  });
  final FootReading left;
  final FootReading right;
  final bool simulated;
  final DateTime receivedAt;

  static SensorSnapshot? fromJson(dynamic j) {
    if (j is! Map) return null;
    return SensorSnapshot(
      left: FootReading.fromJson(j['left']),
      right: FootReading.fromJson(j['right']),
      simulated: j['simulated'] == true,
      receivedAt: DateTime.now(),
    );
  }
}

/// Satu pintu untuk layar: perangkat aktif bisa ESP32 via Bluetooth atau
/// ESP8266 via WiFi, atau perangkat simulasi untuk demo. Urutan prioritas:
/// Bluetooth, WiFi, lalu simulasi.
class DeviceService extends ChangeNotifier {
  DeviceService._() {
    _ble.addListener(notifyListeners);
    _wifi.addListener(notifyListeners);
    _sim.addListener(notifyListeners);
  }
  static final DeviceService instance = DeviceService._();

  final BleService _ble = BleService.instance;
  final WifiService _wifi = WifiService.instance;
  final SimDevice _sim = SimDevice.instance;

  DeviceTransport? get transport {
    if (_ble.isConnected) return DeviceTransport.bluetooth;
    if (_wifi.isConnected) return DeviceTransport.wifi;
    if (_sim.isConnected) return DeviceTransport.simulation;
    return null;
  }

  bool get isConnected => transport != null;

  /// Nama perangkat aktif, mis. "Swavina (Bluetooth)".
  String? get deviceLabel {
    switch (transport) {
      case DeviceTransport.bluetooth:
        return '${_ble.connectedDevice?.name ?? 'Swavina'} (Bluetooth)';
      case DeviceTransport.wifi:
        return '${_wifi.deviceName ?? 'Swavina'} (WiFi)';
      case DeviceTransport.simulation:
        return 'Swavina (Simulasi)';
      case null:
        return null;
    }
  }

  /// Status terakhir yang dilaporkan perangkat.
  String? get deviceStatus {
    switch (transport) {
      case DeviceTransport.bluetooth:
        return _ble.esp32Status;
      case DeviceTransport.wifi:
        return _wifi.deviceStatus;
      case DeviceTransport.simulation:
        return _sim.status;
      case null:
        return null;
    }
  }

  /// Data sensor terbaru (ESP32 via Bluetooth, ESP8266 via WiFi, atau simulasi).
  SensorSnapshot? get sensors => switch (transport) {
        DeviceTransport.bluetooth => _ble.sensors,
        DeviceTransport.wifi => _wifi.sensors,
        DeviceTransport.simulation => _sim.sensors,
        _ => null,
      };

  /// Perbarui data lebih sering (1 detik) selama terapi berjalan.
  void setLiveUpdates(bool on) => _wifi.setLiveUpdates(on);

  Future<void> startTherapy(int temp, int vib, int dur) {
    switch (transport) {
      case DeviceTransport.bluetooth:
        return _ble.startTherapy(temp, vib, dur);
      case DeviceTransport.wifi:
        return _wifi.startTherapy(temp, vib, dur);
      case DeviceTransport.simulation:
        return _sim.startTherapy(temp, vib, dur);
      case null:
        throw DeviceException('Tidak Terhubung', 'Hubungkan perangkat terlebih dahulu.');
    }
  }

  Future<void> stopTherapy() {
    switch (transport) {
      case DeviceTransport.bluetooth:
        return _ble.stopTherapy();
      case DeviceTransport.wifi:
        return _wifi.stopTherapy();
      case DeviceTransport.simulation:
        return _sim.stopTherapy();
      case null:
        throw DeviceException('Tidak Terhubung', 'Hubungkan perangkat terlebih dahulu.');
    }
  }
}
