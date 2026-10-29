import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'device_service.dart';

// ── Ganti dengan UUID dari firmware ESP32 kamu ──────────────────────────────
const String esp32ServiceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
const String esp32CharCommandUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
const String esp32CharStatusUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
const String esp32CharSensorUuid = '6e400004-b5a3-f393-e0a9-e50e24dcca9e';
// ────────────────────────────────────────────────────────────────────────────

/// Nama perangkat ESP32 (harus sama dengan yang di-set di firmware).
const String deviceNamePrefix = 'Swavina';

enum BleStatus { idle, scanning, connecting, connected, disconnected, error }

class BleException extends DeviceException {
  BleException(super.title, super.message);
}

class FoundDevice {
  FoundDevice(this.device, this.name, {this.rssi = 0, this.isSwavina = false});
  final BluetoothDevice device;
  final String name;
  final int rssi;

  /// Kemungkinan besar ESP32 Swavina (nama atau service UUID cocok).
  final bool isSwavina;
  String get id => device.remoteId.str;
}

/// Layanan BLE tunggal (singleton) agar koneksi tetap hidup antar tab.
class BleService extends ChangeNotifier {
  BleService._();
  static final BleService instance = BleService._();

  BleStatus status = BleStatus.idle;
  final List<FoundDevice> foundDevices = [];
  FoundDevice? connectedDevice;

  /// ID perangkat yang sedang dihubungkan (null jika tidak ada).
  String? connectingId;
  String? esp32Status;

  /// Data sensor kaki kiri & kanan (JSON notify tiap detik dari ESP32).
  SensorSnapshot? sensors;

  BluetoothCharacteristic? _commandChar;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _scanStateSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _statusSub;
  StreamSubscription<List<int>>? _sensorSub;

  bool get isConnected => status == BleStatus.connected;

  void _set(BleStatus s) {
    status = s;
    notifyListeners();
  }

  Future<void> _ensurePermissions() async {
    if (!Platform.isAndroid) return;
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  /// Scan perangkat Swavina di sekitar (10 detik).
  /// Melempar [BleException] jika Bluetooth mati.
  Future<void> startScan() async {
    await _ensurePermissions();

    // Di iOS, akses pertama memunculkan dialog izin Bluetooth dan state tetap
    // `unknown` sampai pengguna menjawab — beri waktu cukup.
    BluetoothAdapterState adapter;
    try {
      adapter = await FlutterBluePlus.adapterState
          .firstWhere((s) =>
              s != BluetoothAdapterState.unknown &&
              s != BluetoothAdapterState.turningOn)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      adapter = BluetoothAdapterState.unknown;
    }
    if (adapter != BluetoothAdapterState.on) {
      _set(BleStatus.idle);
      switch (adapter) {
        case BluetoothAdapterState.unauthorized:
          throw BleException('Izin Bluetooth Ditolak',
              'Izinkan Bluetooth untuk Swavina di Pengaturan > Swavina > Bluetooth.');
        case BluetoothAdapterState.unavailable:
          throw BleException('Bluetooth Tidak Tersedia', 'Perangkat ini tidak mendukung Bluetooth LE.');
        case BluetoothAdapterState.unknown:
          throw BleException('Bluetooth Belum Siap', 'Status Bluetooth belum terbaca. Coba lagi.');
        default:
          throw BleException('Bluetooth Mati', 'Aktifkan Bluetooth terlebih dahulu.');
      }
    }

    foundDevices.clear();
    _set(BleStatus.scanning);

    await _scanSub?.cancel();
    // Tampilkan semua perangkat; pengguna yang memilih. Perangkat Swavina
    // (nama atau service UUID cocok) diurutkan paling atas.
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      final devices = results.map((r) {
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.platformName;
        // iOS kadang tidak mengirim nama (cache / scan response), jadi
        // cocokkan juga lewat service UUID yang diiklankan ESP32.
        final hasService = r.advertisementData.serviceUuids
            .contains(Guid(esp32ServiceUuid));
        return FoundDevice(
          r.device,
          name.isNotEmpty ? name : 'Perangkat tanpa nama',
          rssi: r.rssi,
          isSwavina: name.startsWith(deviceNamePrefix) || hasService,
        );
      }).toList()
        ..sort((a, b) {
          if (a.isSwavina != b.isSwavina) return a.isSwavina ? -1 : 1;
          final aNamed = a.device.platformName.isNotEmpty;
          final bNamed = b.device.platformName.isNotEmpty;
          if (aNamed != bNamed) return aNamed ? -1 : 1;
          return b.rssi.compareTo(a.rssi);
        });
      foundDevices
        ..clear()
        ..addAll(devices);
      notifyListeners();
    });

    await _scanStateSub?.cancel();
    _scanStateSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && status == BleStatus.scanning) _set(BleStatus.idle);
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (e) {
      debugPrint('BLE startScan error: $e');
      _set(BleStatus.error);
      throw BleException('Scan Gagal', 'Tidak bisa memulai scan Bluetooth. Coba lagi.');
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    if (status == BleStatus.scanning) _set(BleStatus.idle);
  }

  /// Hubungkan ke perangkat. Melempar [BleException] jika gagal.
  Future<void> connect(FoundDevice found) async {
    await stopScan();
    connectingId = found.id;
    _set(BleStatus.connecting);

    try {
      final device = found.device;
      await device.connect(timeout: const Duration(seconds: 10));
      final services = await device.discoverServices();

      final service = services.firstWhere(
        (s) => s.uuid == Guid(esp32ServiceUuid),
        orElse: () => throw BleException('Koneksi Gagal', 'Service ESP32 tidak ditemukan. Pastikan perangkat yang dipilih adalah ESP32 Swavina.'),
      );

      _commandChar = null;
      BluetoothCharacteristic? statusChar, sensorChar;
      for (final c in service.characteristics) {
        if (c.uuid == Guid(esp32CharCommandUuid)) _commandChar = c;
        if (c.uuid == Guid(esp32CharStatusUuid)) statusChar = c;
        if (c.uuid == Guid(esp32CharSensorUuid)) sensorChar = c;
      }
      if (_commandChar == null) {
        throw BleException('Koneksi Gagal', 'Characteristic perintah tidak ditemukan.');
      }

      connectedDevice = found;

      // Monitor status dari ESP32
      if (statusChar != null) {
        await statusChar.setNotifyValue(true);
        await _statusSub?.cancel();
        _statusSub = statusChar.onValueReceived.listen((value) {
          esp32Status = utf8.decode(value, allowMalformed: true);
          notifyListeners();
        });
      }

      // Data sensor (firmware lama tanpa characteristic ini tetap bisa dipakai)
      sensors = null;
      await _sensorSub?.cancel();
      if (sensorChar != null) {
        await sensorChar.setNotifyValue(true);
        _sensorSub = sensorChar.onValueReceived.listen((value) {
          try {
            sensors = SensorSnapshot.fromJson(jsonDecode(utf8.decode(value)));
            notifyListeners();
          } catch (_) {
            // Paket terpotong / bukan JSON: abaikan, tunggu pembacaan berikutnya.
          }
        });
      }

      // Handle disconnect otomatis
      await _connSub?.cancel();
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected &&
            status == BleStatus.connected) {
          _commandChar = null;
          connectedDevice = null;
          sensors = null;
          _set(BleStatus.disconnected);
        }
      });

      connectingId = null;
      _set(BleStatus.connected);
    } catch (e) {
      connectingId = null;
      // Perangkat yang dipilih mungkin bukan ESP32 Swavina — lepaskan lagi.
      try {
        await found.device.disconnect();
      } catch (_) {}
      _commandChar = null;
      connectedDevice = null;
      _set(BleStatus.error);
      if (e is BleException) rethrow;
      throw BleException(
        'Koneksi Gagal',
        'Tidak bisa terhubung ke perangkat. Coba lagi.',
      );
    }
  }

  /// Kirim perintah JSON ke ESP32. Melempar [BleException] jika gagal.
  Future<void> _sendCommand(Map<String, dynamic> command) async {
    final char = _commandChar;
    if (char == null || !isConnected) {
      throw BleException('Tidak Terhubung', 'Hubungkan perangkat terlebih dahulu.');
    }
    try {
      await char.write(utf8.encode(jsonEncode(command)));
    } catch (_) {
      throw BleException('Gagal Kirim', 'Perintah tidak terkirim ke perangkat.');
    }
  }

  Future<void> startTherapy(int temp, int vib, int dur) =>
      _sendCommand({'cmd': 'start', 'temp': temp, 'vib': vib, 'dur': dur});

  Future<void> stopTherapy() => _sendCommand({'cmd': 'stop'});

  Future<void> disconnect() async {
    final dev = connectedDevice?.device;
    await _connSub?.cancel();
    await _statusSub?.cancel();
    await _sensorSub?.cancel();
    try {
      await dev?.disconnect();
    } catch (_) {}
    _commandChar = null;
    connectedDevice = null;
    esp32Status = null;
    sensors = null;
    _set(BleStatus.idle);
  }
}
