import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/ble_service.dart';
import '../core/device_service.dart';
import '../core/local_db.dart';
import '../core/sim_device.dart';
import '../core/theme.dart';
import '../core/wifi_service.dart';
import '../widgets/common.dart';
import '../widgets/swavina_scaffold.dart';
import 'wifi_setup_screen.dart';

class TherapyScreen extends StatefulWidget {
  const TherapyScreen({super.key});

  @override
  State<TherapyScreen> createState() => _TherapyScreenState();
}

class _TherapyScreenState extends State<TherapyScreen> {
  final BleService _ble = BleService.instance;
  final WifiService _wifi = WifiService.instance;
  final DeviceService _device = DeviceService.instance;
  final SimDevice _sim = SimDevice.instance;
  DeviceTransport _sheetTab = DeviceTransport.bluetooth;
  final _manualIp = TextEditingController();
  bool _showManualIp = false;
  bool _wifiSearched = false;

  bool _isRunning = false;
  int _temperature = 38;
  int _vibration = 45;
  int _duration = 20;
  int _seconds = 0;
  DateTime? _startedAt;

  // Statistik sensor selama sesi (dikirim ke server untuk log keamanan).
  double? _maxTemp;
  double _tempSum = 0, _vibSum = 0;
  int _tempN = 0, _vibN = 0;
  DateTime? _lastSample;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    AppState.therapyRequest.addListener(_onRequest);
    _device.addListener(_sampleSensors);
  }

  @override
  void dispose() {
    AppState.therapyRequest.removeListener(_onRequest);
    _device.removeListener(_sampleSensors);
    _timer?.cancel();
    _device.setLiveUpdates(false);
    _manualIp.dispose();
    super.dispose();
  }

  /* ===== PARAMETER DARI SCHEDULE ===== */
  Future<void> _onRequest() async {
    final req = AppState.therapyRequest.value;
    if (req == null) return;
    AppState.therapyRequest.value = null;

    setState(() {
      _duration = req.duration;
      _temperature = req.temperature.clamp(minTemperature, maxTemperature);
      _vibration = req.vibration;
    });

    if (!req.fromSchedule) return;
    if (_isRunning) return;

    if (!_device.isConnected) {
      await showAlert(context, 'Tidak Terhubung',
          'Tidak bisa memulai terapi terjadwal, perangkat belum terhubung.');
      return;
    }
    await _start();
  }

  /* ===== TIMER ===== */
  String get _timeLabel {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
      if (_seconds >= _duration * 60) _finish();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /* ===== START / STOP ===== */
  Future<void> _start() async {
    try {
      await _device.startTherapy(_temperature, _vibration, _duration);
      _device.setLiveUpdates(true);
      setState(() {
        _seconds = 0;
        _startedAt = DateTime.now();
        _maxTemp = null;
        _tempSum = _vibSum = 0;
        _tempN = _vibN = 0;
        _isRunning = true;
      });
      _startTimer();
    } on DeviceException catch (e) {
      if (mounted) await showAlert(context, e.title, e.message);
    }
  }

  /// Dihentikan manual: simpan dengan durasi yang benar-benar berjalan.
  Future<void> _stop() async {
    if (!_isRunning) return;
    _stopTimer();
    _device.setLiveUpdates(false);
    final elapsed = _seconds;
    setState(() => _isRunning = false);

    DeviceException? error;
    try {
      await _device.stopTherapy();
    } on DeviceException catch (e) {
      error = e;
    }

    // Dibulatkan ke atas (min. 1 menit) agar sesi singkat tetap tercatat.
    await _saveSession(((elapsed + 59) ~/ 60).clamp(1, _duration), completed: false);
    if (!mounted) return;
    if (error != null) {
      await showAlert(context, error.title, error.message);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Terapi dihentikan dan disimpan ke History')),
      );
    }
  }

  Future<void> _toggle() async {
    if (!_device.isConnected) {
      await showAlert(context, 'Tidak Terhubung',
          'Hubungkan perangkat Swavina lewat Bluetooth atau WiFi terlebih dahulu.');
      return;
    }
    _isRunning ? await _stop() : await _start();
  }

  /* ===== AUTO STOP: target durasi tercapai ===== */
  Future<void> _finish() async {
    if (!_isRunning) return;
    _stopTimer();
    _device.setLiveUpdates(false);
    setState(() => _isRunning = false);

    try {
      await _device.stopTherapy();
    } catch (_) {}

    await _saveSession(_duration, completed: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Terapi selesai dan disimpan ke History')),
      );
    }
  }

  /* ===== SIMPAN SESI: SQLite lokal + kirim ke server ===== */
  /// Catat pembacaan sensor kedua kaki (sekali per data baru) selama terapi.
  void _sampleSensors() {
    final s = _device.sensors;
    if (!_isRunning || s == null || s.receivedAt == _lastSample) return;
    _lastSample = s.receivedAt;
    for (final f in [s.left, s.right]) {
      final t = f.temp;
      if (t != null) {
        _maxTemp = _maxTemp == null || t > _maxTemp! ? t : _maxTemp;
        _tempSum += t;
        _tempN++;
      }
      if (f.vib != null) {
        _vibSum += f.vib!;
        _vibN++;
      }
    }
  }

  Future<void> _saveSession(int durationMinutes, {required bool completed}) async {
    final start = _startedAt ?? DateTime.now();
    _startedAt = null;
    final date = DateFormat('yyyy-MM-dd').format(start);
    final time = DateFormat('HH:mm:ss').format(start);

    await LocalDb.insertTherapy(
      date: date,
      startTime: time,
      duration: durationMinutes,
      temperature: _temperature,
      vibration: _vibration,
    );

    try {
      await Api.post('/therapy', {
        'date': date,
        'start_time': time,
        'duration': durationMinutes,
        'temperature': _temperature,
        'vibration': _vibration,
        'status': completed ? 'completed' : 'stopped',
        'target_duration': _duration,
        if (!completed) 'stop_reason': 'Dihentikan pasien',
        if (_maxTemp != null) 'max_temp': double.parse(_maxTemp!.toStringAsFixed(1)),
        if (_tempN > 0) 'avg_temp': double.parse((_tempSum / _tempN).toStringAsFixed(1)),
        if (_vibN > 0) 'avg_vib': double.parse((_vibSum / _vibN).toStringAsFixed(1)),
        if (_device.transport != null) 'transport': _device.transport!.name,
      });
    } catch (_) {
      // Offline: data tetap tersimpan di SQLite lokal.
    }
  }

  /* ===== DEVICE SHEET (BLUETOOTH / WIFI) ===== */
  ({String label, Color color}) _statusInfo() {
    if (_device.isConnected) {
      return (label: 'Terhubung — ${_device.deviceLabel ?? ''}', color: AppColors.success);
    }
    switch (_ble.status) {
      case BleStatus.scanning:
        return (label: 'Mencari perangkat...', color: AppColors.warning);
      case BleStatus.connecting:
        return (label: 'Menghubungkan...', color: AppColors.warning);
      case BleStatus.error:
        return (label: 'Koneksi Error', color: AppColors.danger);
      case BleStatus.disconnected:
        return (label: 'Terputus', color: AppColors.danger);
      case BleStatus.connected:
      case BleStatus.idle:
        break;
    }
    switch (_wifi.status) {
      case WifiStatus.connecting:
        return (label: 'Mencari perangkat WiFi...', color: AppColors.warning);
      case WifiStatus.disconnected:
        return (label: 'Perangkat WiFi offline', color: AppColors.danger);
      case WifiStatus.connected:
      case WifiStatus.idle:
        return (label: 'Tidak Terhubung', color: AppColors.danger);
    }
  }

  Future<void> _runDevice(Future<void> Function() action) async {
    try {
      await action();
    } on DeviceException catch (e) {
      if (mounted) await showAlert(context, e.title, e.message);
    }
  }

  void _openDeviceSheet() {
    final c = AppColors.of(context);
    if (_sheetTab == DeviceTransport.wifi) _autoDiscoverWifi();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) => ListenableBuilder(
            listenable: _device,
            builder: (ctx, _) {
              final info = _statusInfo();
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Perangkat',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.textPrimary)),
                        IconButton(
                          icon: Icon(Icons.close, color: c.textPrimary),
                          onPressed: () {
                            _ble.stopScan();
                            Navigator.pop(ctx);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: info.color.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(info.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: info.color, fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<DeviceTransport>(
                        segments: const [
                          ButtonSegment(
                              value: DeviceTransport.bluetooth,
                              icon: Icon(Icons.bluetooth),
                              label: Text('Bluetooth')),
                          ButtonSegment(
                              value: DeviceTransport.wifi, icon: Icon(Icons.wifi), label: Text('WiFi')),
                          ButtonSegment(
                              value: DeviceTransport.simulation,
                              icon: Icon(Icons.science_outlined),
                              label: Text('Simulasi')),
                        ],
                        selected: {_sheetTab},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) {
                          if (s.first != DeviceTransport.bluetooth) _ble.stopScan();
                          setSheetState(() => _sheetTab = s.first);
                          if (s.first == DeviceTransport.wifi) _autoDiscoverWifi();
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    switch (_sheetTab) {
                      DeviceTransport.bluetooth => _bleSection(c),
                      DeviceTransport.wifi => _wifiSection(ctx, c, setSheetState),
                      DeviceTransport.simulation => _simSection(c),
                    },
                  ],
                ),
              );
            },
          ),
        );
      },
    ).whenComplete(_ble.stopScan);
  }

  Widget _bleSection(AppColors c) {
    final scanning = _ble.status == BleStatus.scanning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_ble.isConnected)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => scanning ? _ble.stopScan() : _runDevice(_ble.startScan),
              style: ElevatedButton.styleFrom(
                backgroundColor: scanning ? AppColors.warning : AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search, size: 18),
              label: Text(scanning ? 'Menghentikan Scan...' : 'Scan Perangkat',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
        if (_ble.foundDevices.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Perangkat Ditemukan (${_ble.foundDevices.length})',
              style: TextStyle(fontWeight: FontWeight.w600, color: c.textSecondary)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final d in _ble.foundDevices)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _ble.connectingId != null ? null : () => _runDevice(() => _ble.connect(d)),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.cardAlt,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.bluetooth,
                              size: 20, color: d.isSwavina ? AppColors.accent : c.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(d.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 15, fontWeight: FontWeight.w600, color: c.textPrimary)),
                                    ),
                                    if (d.isSwavina) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.accent.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text('Swavina',
                                            style: TextStyle(
                                                fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent)),
                                      ),
                                    ],
                                  ],
                                ),
                                Text('${d.id} · ${d.rssi} dBm',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: c.textSecondary)),
                              ],
                            ),
                          ),
                          if (_ble.connectingId == d.id)
                            const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (_ble.foundDevices.isEmpty && _ble.status == BleStatus.idle)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'Tekan "Scan Perangkat" untuk melihat perangkat Bluetooth di sekitar, lalu pilih ESP32 Swavina.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.5, color: c.textSecondary),
            ),
          ),
        if (_ble.isConnected) ...[
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Putuskan Koneksi',
            color: AppColors.danger,
            onPressed: _ble.disconnect,
          ),
        ],
      ],
    );
  }

  Widget _simSection(AppColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Mode demo tanpa perangkat: aplikasi meniru kaus kaki Swavina, lengkap dengan data sensor '
          'suhu & getaran kedua kaki. Sesi tetap tersimpan ke History dengan koneksi "simulation".',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.5, color: c.textSecondary),
        ),
        const SizedBox(height: 16),
        if (_sim.isConnected)
          PrimaryButton(
            label: 'Matikan Simulasi',
            color: AppColors.danger,
            onPressed: _isRunning ? null : _sim.disconnect,
          )
        else
          PrimaryButton(
            label: 'Mulai Simulasi',
            color: AppColors.warning,
            onPressed: _device.isConnected ? null : _sim.connect,
          ),
        if (!_sim.isConnected && _device.isConnected)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Putuskan perangkat yang terhubung untuk memakai simulasi.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.textSecondary)),
          ),
      ],
    );
  }

  /// Cari otomatis saat tab WiFi dibuka dan belum ada perangkat tersimpan
  /// (mis. WiFi perangkat diatur lewat halaman web, bukan lewat aplikasi).
  void _autoDiscoverWifi() {
    if (_wifi.isConfigured || _wifi.status == WifiStatus.connecting) return;
    _wifiSearched = true;
    _wifi.discover();
  }

  Widget _wifiSection(BuildContext sheetCtx, AppColors c, StateSetter setSheetState) {
    final searching = _wifi.status == WifiStatus.connecting;

    if (!_wifi.isConfigured) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (searching)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
                const SizedBox(width: 10),
                Text('Mencari perangkat di WiFi ini...', style: TextStyle(color: c.textSecondary)),
              ],
            )
          else
            Text(
              _wifiSearched
                  ? 'Perangkat belum ditemukan di WiFi ini. Pastikan HP dan perangkat memakai WiFi yang sama, '
                      'atau masukkan IP perangkat (lihat di http://swavina.local).'
                  : 'Cari perangkat yang sudah terhubung ke WiFi yang sama dengan HP ini.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.5, color: c.textSecondary),
            ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: searching ? 'Mencari...' : 'Cari Perangkat di WiFi Ini',
            onPressed: searching
                ? null
                : () {
                    _wifiSearched = true;
                    _runDevice(_findWifiDevice);
                  },
          ),
          if (_showManualIp) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualIp,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: c.textPrimary, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'IP, mis. 192.168.1.33',
                      hintStyle: TextStyle(color: c.textSecondary),
                      isDense: true,
                      contentPadding: const EdgeInsets.all(14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: searching ? null : () => _runDevice(() => _wifi.connectManual(_manualIp.text)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.vibration,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Hubungkan'),
                ),
              ],
            ),
          ] else
            TextButton(
              onPressed: () => setSheetState(() => _showManualIp = true),
              child: const Text('Masukkan IP manual'),
            ),
          Divider(height: 24, color: c.border),
          Text(
            'Perangkat baru / belum punya WiFi? HP akan masuk sebentar ke WiFi perangkat '
            '("$esp8266ApSsidPrefix…") untuk mengirim nama & password WiFi rumah.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.5, color: c.textSecondary),
          ),
          TextButton(onPressed: _openWifiSetup, child: const Text('Setup WiFi Perangkat')),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.cardAlt, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Icon(_wifi.isConnected ? Icons.wifi : Icons.wifi_off,
                  size: 20, color: _wifi.isConnected ? AppColors.success : c.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_wifi.deviceName ?? 'Swavina',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textPrimary)),
                    Text('${_wifi.host} · ${_wifi.isConnected ? 'online' : 'offline'}',
                        style: TextStyle(fontSize: 12, color: c.textSecondary)),
                  ],
                ),
              ),
              if (searching)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!_wifi.isConnected)
          PrimaryButton(
            label: searching ? 'Mencari...' : 'Hubungkan Lagi',
            onPressed: searching ? null : () => _runDevice(_findWifiDevice),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _openWifiSetup,
                child: const Text('Ganti WiFi'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () async {
                  if (await confirmDelete(sheetCtx, 'Lupakan perangkat WiFi ini dari aplikasi?')) {
                    await _wifi.forget();
                  }
                },
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('Lupakan'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _findWifiDevice() async {
    if (!await _wifi.discover()) {
      throw WifiException('Perangkat Tidak Ditemukan',
          'Pastikan perangkat menyala dan terhubung ke WiFi yang sama dengan HP ini.');
    }
  }

  Future<void> _openWifiSetup() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const WifiSetupScreen()),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Terhubung ke ${_wifi.deviceName ?? 'perangkat'} lewat WiFi')),
      );
    }
  }

  /* ===== UI ===== */
  /* ===== SENSOR REALTIME ===== */
  Widget _sensorCard(AppColors c) {
    final s = _device.sensors;
    final stale = s == null || DateTime.now().difference(s.receivedAt) > const Duration(seconds: 5);

    return CardBox(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sensors, size: 20, color: stale ? c.textSecondary : AppColors.success),
              const SizedBox(width: 8),
              Text('Sensor Realtime',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.textPrimary)),
              const Spacer(),
              if (s?.simulated == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Simulasi',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.warning)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Target: $_temperature°C · $_vibration Hz',
              style: TextStyle(fontSize: 13, color: c.textSecondary)),
          const SizedBox(height: 12),
          if (s == null)
            Text(
              _device.transport == DeviceTransport.wifi || _device.transport == DeviceTransport.bluetooth
                  ? 'Menunggu data sensor...'
                  : 'Data sensor belum tersedia untuk koneksi ini.',
              style: TextStyle(color: c.textSecondary),
            )
          else
            Row(
              children: [
                Expanded(child: _footTile(c, 'Kaki Kiri', s.left, stale)),
                const SizedBox(width: 10),
                Expanded(child: _footTile(c, 'Kaki Kanan', s.right, stale)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _footTile(AppColors c, String label, FootReading f, bool stale) {
    Widget metric(IconData icon, Color color, String value, String unit, double? actual, int target) {
      // Hijau bila sudah dekat target, oranye bila masih menuju target.
      final near = actual != null && (actual - target).abs() <= (unit == '°C' ? 0.5 : 2);
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: stale ? c.textSecondary : c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
            const SizedBox(width: 3),
            Text(unit, style: TextStyle(fontSize: 13, color: c.textSecondary)),
            const Spacer(),
            if (actual != null && !stale)
              Icon(near ? Icons.check_circle : Icons.trending_up,
                  size: 16, color: near ? AppColors.success : AppColors.warning),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.cardAlt, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: c.textPrimary)),
          metric(Icons.thermostat, AppColors.accent, f.temp?.toStringAsFixed(1) ?? '--', '°C', f.temp,
              _temperature),
          metric(Icons.vibration, AppColors.vibration, f.vib?.toStringAsFixed(1) ?? '--', 'Hz', f.vib,
              _vibration),
        ],
      ),
    );
  }

  Widget _control({
    required AppColors c,
    required String title,
    required String value,
    required double min,
    required double max,
    required int current,
    required Color color,
    required ValueChanged<int> onChanged,
  }) {
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
          Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: c.textPrimary)),
          Slider(
            min: min,
            max: max,
            divisions: (max - min).round(),
            value: current.toDouble(),
            activeColor: color,
            inactiveColor: c.sliderTrack,
            thumbColor: color,
            onChanged: _isRunning ? null : (v) => onChanged(v.round()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return ListenableBuilder(
      listenable: _device,
      builder: (context, _) {
        final info = _statusInfo();
        return SwavinaScaffold(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Therapy',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c.textPrimary)),
                    IconButton(
                      onPressed: _openDeviceSheet,
                      icon: Icon(Icons.settings_outlined, size: 26, color: c.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // STATUS PERANGKAT
                CardBox(
                  radius: 18,
                  padding: const EdgeInsets.all(16),
                  onTap: _openDeviceSheet,
                  child: Row(
                    children: [
                      Icon(
                          switch (_device.transport) {
                            DeviceTransport.wifi => Icons.wifi,
                            DeviceTransport.simulation => Icons.science_outlined,
                            _ => Icons.bluetooth,
                          },
                          size: 24,
                          color: info.color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Status Perangkat',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
                            Text(info.label,
                                style: TextStyle(color: info.color, fontWeight: FontWeight.w600)),
                            if (_device.deviceStatus != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text('Perangkat: ${_device.deviceStatus}',
                                    style: TextStyle(fontSize: 12, color: c.textSecondary)),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 20, color: c.textSecondary),
                    ],
                  ),
                ),
                if (!_device.isConnected)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: OutlinedButton.icon(
                      onPressed: _sim.connect,
                      icon: const Icon(Icons.science_outlined, size: 18),
                      label: const Text('Tidak ada perangkat? Coba Mode Simulasi'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        side: const BorderSide(color: AppColors.warning),
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),

                // TIMER
                CardBox(
                  radius: 24,
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.only(bottom: 20),
                  color: AppColors.accent,
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        const Text('Session Time', style: TextStyle(color: Colors.white, fontSize: 16)),
                        Text(_timeLabel,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 42,
                                fontWeight: FontWeight.w800,
                                fontFeatures: [FontFeature.tabularFigures()])),
                        const SizedBox(height: 4),
                        Text('Target: $_duration menit',
                            style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                ),

                if (_isRunning) _sensorCard(c),

                _control(
                  c: c,
                  title: 'Therapy Duration',
                  value: '$_duration min',
                  min: 1,
                  max: 60,
                  current: _duration,
                  color: AppColors.durationGreen,
                  onChanged: (v) => setState(() => _duration = v),
                ),
                _control(
                  c: c,
                  title: 'Temperature',
                  value: '$_temperature°C',
                  min: minTemperature.toDouble(),
                  max: maxTemperature.toDouble(),
                  current: _temperature,
                  color: AppColors.accent,
                  onChanged: (v) => setState(() => _temperature = v),
                ),
                _control(
                  c: c,
                  title: 'Vibration',
                  value: '$_vibration Hz',
                  min: 30,
                  max: 60,
                  current: _vibration,
                  color: AppColors.vibration,
                  onChanged: (v) => setState(() => _vibration = v),
                ),

                PrimaryButton(
                  label: _isRunning ? 'STOP THERAPY' : 'START THERAPY',
                  color: _isRunning ? AppColors.danger : AppColors.success,
                  radius: 20,
                  fontSize: 18,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  onPressed: _toggle,
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        );
      },
    );
  }
}
