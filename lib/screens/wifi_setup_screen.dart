import 'package:flutter/material.dart';

import '../core/device_service.dart';
import '../core/theme.dart';
import '../core/wifi_service.dart';
import '../widgets/common.dart';

enum _Step { joinAp, credentials, provisioning, findDevice }

/// Wizard setup WiFi perangkat ESP8266:
/// 1. HP masuk ke WiFi perangkat (Swavina-XXXX)
/// 2. Pilih / ketik SSID + password WiFi rumah
/// 3. Perangkat terhubung ke WiFi rumah
/// 4. HP kembali ke WiFi rumah, aplikasi mencari perangkat
///
/// Mengembalikan `true` lewat [Navigator.pop] jika perangkat terhubung.
class WifiSetupScreen extends StatefulWidget {
  const WifiSetupScreen({super.key});

  @override
  State<WifiSetupScreen> createState() => _WifiSetupScreenState();
}

class _WifiSetupScreenState extends State<WifiSetupScreen> {
  final WifiService _wifi = WifiService.instance;
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  final _manualIp = TextEditingController();

  _Step _step = _Step.joinAp;
  bool _busy = false;
  bool _showPassword = false;
  bool _showManualIp = false;
  bool _scanning = false;
  String _apName = 'Swavina';
  String? _deviceIp;
  List<WifiNetwork> _networks = [];

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    _manualIp.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on DeviceException catch (e) {
      if (mounted) await showAlert(context, e.title, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /* ===== LANGKAH 1: HP SUDAH DI AP PERANGKAT ===== */
  Future<void> _checkAp() => _guard(() async {
        _apName = await _wifi.apInfo();
        setState(() => _step = _Step.credentials);
        _scanNetworks();
      });

  Future<void> _scanNetworks() async {
    setState(() => _scanning = true);
    final nets = await _wifi.apScan();
    if (!mounted) return;
    setState(() {
      _networks = nets;
      _scanning = false;
    });
  }

  /* ===== LANGKAH 2–3: KIRIM SSID & PASSWORD ===== */
  Future<void> _sendCredentials() async {
    final ssid = _ssid.text.trim();
    if (ssid.isEmpty) {
      await showAlert(context, 'Nama WiFi Kosong', 'Pilih atau ketik nama WiFi (SSID) rumah.');
      return;
    }
    await _guard(() async {
      await _wifi.apSendCredentials(ssid, _password.text);
      setState(() => _step = _Step.provisioning);
      try {
        final res = await _wifi.apWaitForIp();
        _deviceIp = res.ip;
        if (mounted) setState(() => _step = _Step.findDevice);
      } on DeviceException {
        if (mounted) setState(() => _step = _Step.credentials);
        rethrow;
      }
    });
  }

  /* ===== LANGKAH 4: CARI PERANGKAT DI WIFI RUMAH ===== */
  Future<void> _findDevice() => _guard(() async {
        final ok = await _wifi.discover(hintIp: _deviceIp);
        if (!mounted) return;
        if (ok) {
          Navigator.pop(context, true);
        } else {
          setState(() => _showManualIp = true);
          throw WifiException(
            'Perangkat Belum Ditemukan',
            'Pastikan HP sudah kembali ke WiFi "${_ssid.text.trim()}" dan perangkat menyala, lalu coba lagi. '
                'Kamu juga bisa memasukkan IP perangkat secara manual.',
          );
        }
      });

  Future<void> _connectManual() => _guard(() async {
        await _wifi.connectManual(_manualIp.text);
        if (mounted) Navigator.pop(context, true);
      });

  /* ===== UI ===== */
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final stepIndex = _Step.values.indexOf(_step);

    return Scaffold(
      appBar: AppBar(title: const Text('Setup WiFi Perangkat'), backgroundColor: c.pageBg),
      backgroundColor: c.pageBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                for (var i = 0; i < _Step.values.length; i++)
                  Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: i < _Step.values.length - 1 ? 6 : 0),
                      decoration: BoxDecoration(
                        color: i <= stepIndex ? AppColors.accent : c.progressBg,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Langkah ${stepIndex + 1} dari ${_Step.values.length}',
                style: TextStyle(fontSize: 13, color: c.textSecondary)),
            const SizedBox(height: 16),
            switch (_step) {
              _Step.joinAp => _joinApStep(c),
              _Step.credentials => _credentialsStep(c),
              _Step.provisioning => _provisioningStep(c),
              _Step.findDevice => _findDeviceStep(c),
            },
          ],
        ),
      ),
    );
  }

  Widget _title(AppColors c, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.textPrimary)),
      );

  Widget _body(AppColors c, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: TextStyle(fontSize: 15, height: 1.5, color: c.textSecondary)),
      );

  Widget _numbered(AppColors c, List<String> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(items[i], style: TextStyle(fontSize: 15, height: 1.4, color: c.textPrimary)),
                  ),
                ],
              ),
            ),
        ],
      );

  InputDecoration _deco(AppColors c, String hint, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: c.textSecondary),
        contentPadding: const EdgeInsets.all(14),
        suffixIcon: suffix,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      );

  Widget _joinApStep(AppColors c) => CardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.wifi_tethering, size: 36, color: AppColors.accent),
            const SizedBox(height: 10),
            _title(c, 'Sambungkan HP ke WiFi Perangkat'),
            _numbered(c, [
              'Nyalakan perangkat Swavina (ESP8266).',
              'Buka Pengaturan → WiFi di HP.',
              'Pilih jaringan "$esp8266ApSsidPrefix…" (password default: swavina123).',
              'Kembali ke aplikasi ini lalu tekan Lanjut.',
            ]),
            _body(c,
                'Jika HP memberi tahu jaringan tidak memiliki internet, pilih tetap terhubung. '
                'Di Android, matikan data seluler sementara bila perangkat tidak terdeteksi.'),
            const SizedBox(height: 6),
            PrimaryButton(
              label: _busy ? 'Memeriksa...' : 'Saya Sudah Terhubung, Lanjut',
              onPressed: _busy ? null : _checkAp,
            ),
          ],
        ),
      );

  Widget _credentialsStep(AppColors c) => CardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(c, 'WiFi untuk $_apName'),
            _body(c, 'Pilih WiFi rumah yang juga dipakai HP ini, lalu masukkan password-nya.'),
            Row(
              children: [
                Text('Jaringan terdeteksi',
                    style: TextStyle(fontWeight: FontWeight.w600, color: c.textSecondary)),
                const Spacer(),
                if (_scanning)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                else
                  TextButton.icon(
                    onPressed: _busy ? null : _scanNetworks,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Scan'),
                  ),
              ],
            ),
            if (!_scanning && _networks.isEmpty)
              _body(c, 'Tidak ada daftar jaringan. Ketik nama WiFi secara manual.'),
            if (_networks.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final n in _networks)
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: Icon(_signalIcon(n.rssi),
                            color: _ssid.text == n.ssid ? AppColors.accent : c.textSecondary),
                        title: Text(n.ssid, style: TextStyle(color: c.textPrimary, fontSize: 15)),
                        trailing: n.secure ? Icon(Icons.lock_outline, size: 16, color: c.textSecondary) : null,
                        selected: _ssid.text == n.ssid,
                        onTap: () => setState(() => _ssid.text = n.ssid),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _ssid,
              autocorrect: false,
              style: TextStyle(color: c.textPrimary, fontSize: 16),
              decoration: _deco(c, 'Nama WiFi (SSID)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: !_showPassword,
              autocorrect: false,
              style: TextStyle(color: c.textPrimary, fontSize: 16),
              decoration: _deco(
                c,
                'Password WiFi',
                suffix: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, color: c.textSecondary),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: _busy ? 'Mengirim...' : 'Kirim ke Perangkat',
              color: AppColors.success,
              onPressed: _busy ? null : _sendCredentials,
            ),
          ],
        ),
      );

  IconData _signalIcon(int rssi) {
    if (rssi >= -60) return Icons.network_wifi;
    if (rssi >= -75) return Icons.network_wifi_3_bar;
    return Icons.network_wifi_1_bar;
  }

  Widget _provisioningStep(AppColors c) => CardBox(
        child: Column(
          children: [
            const SizedBox(height: 10),
            const CircularProgressIndicator(color: AppColors.accent),
            const SizedBox(height: 20),
            _title(c, 'Menghubungkan Perangkat...'),
            _body(c,
                'Perangkat sedang masuk ke WiFi "${_ssid.text.trim()}". Proses ini bisa memakan waktu hingga 30 detik.'),
          ],
        ),
      );

  Widget _findDeviceStep(AppColors c) => CardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_deviceIp != null ? Icons.check_circle : Icons.wifi_find,
                size: 36, color: _deviceIp != null ? AppColors.success : AppColors.accent),
            const SizedBox(height: 10),
            _title(c, _deviceIp != null ? 'Perangkat Terhubung ke WiFi' : 'Data WiFi Terkirim'),
            if (_deviceIp != null) _body(c, 'IP perangkat: $_deviceIp'),
            _numbered(c, [
              'Buka Pengaturan → WiFi di HP.',
              'Sambungkan kembali ke "${_ssid.text.trim()}".',
              'Kembali ke aplikasi lalu tekan Cari Perangkat.',
            ]),
            const SizedBox(height: 6),
            PrimaryButton(
              label: _busy ? 'Mencari...' : 'Cari Perangkat',
              onPressed: _busy ? null : _findDevice,
            ),
            if (_showManualIp) ...[
              const SizedBox(height: 20),
              Text('Masukkan IP manual',
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.textSecondary)),
              const SizedBox(height: 8),
              TextField(
                controller: _manualIp,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: c.textPrimary, fontSize: 16),
                decoration: _deco(c, 'mis. 192.168.1.50'),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Hubungkan ke IP',
                color: AppColors.vibration,
                onPressed: _busy ? null : _connectManual,
              ),
            ],
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _busy ? null : () => setState(() => _step = _Step.joinAp),
                child: const Text('Ulangi Setup'),
              ),
            ),
          ],
        ),
      );
}
