import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_service.dart';

// ── Samakan dengan firmware ESP8266 (firmware/esp8266_swavina) ──────────────
/// IP perangkat saat mode Access Point (default ESP8266).
const String esp8266ApHost = '192.168.4.1';

/// Hostname mDNS perangkat di jaringan rumah (`MDNS.begin("swavina")`).
const String esp8266MdnsHost = 'swavina.local';

/// Prefix SSID access point perangkat, mis. "Swavina-1A2B".
const String esp8266ApSsidPrefix = 'Swavina-';
// ────────────────────────────────────────────────────────────────────────────

enum WifiStatus { idle, connecting, connected, disconnected }

class WifiException extends DeviceException {
  WifiException(super.title, super.message);
}

/// Jaringan WiFi yang terlihat oleh perangkat (hasil `/scan`).
class WifiNetwork {
  WifiNetwork(this.ssid, this.rssi, this.secure);
  final String ssid;
  final int rssi;
  final bool secure;
}

/// Hasil menunggu perangkat terhubung ke WiFi rumah.
class ProvisionResult {
  ProvisionResult({this.ip, this.lostConnection = false});

  /// IP perangkat di jaringan rumah (null jika belum diketahui).
  final String? ip;

  /// HP terputus dari AP perangkat sebelum IP terbaca (normal pada ESP8266
  /// karena kanal AP ikut berpindah). Perangkat dicari lewat mDNS setelahnya.
  final bool lostConnection;
}

/// Koneksi ke perangkat ESP8266 lewat WiFi (HTTP di jaringan lokal).
///
/// Alur setup: HP masuk ke AP perangkat → kirim SSID & password WiFi rumah
/// ke `192.168.4.1` → perangkat terhubung ke WiFi rumah → HP kembali ke WiFi
/// rumah → perangkat dicari lewat IP / `swavina.local`.
class WifiService extends ChangeNotifier {
  WifiService._();
  static final WifiService instance = WifiService._();

  static const _hostKey = 'WIFI_DEVICE_HOST';
  static const _nameKey = 'WIFI_DEVICE_NAME';

  WifiStatus status = WifiStatus.idle;

  /// IP / hostname perangkat di jaringan rumah (tersimpan).
  String? host;
  String? deviceName;
  String? deviceStatus;
  SensorSnapshot? sensors;

  Timer? _pingTimer;
  bool _pinging = false;
  bool _live = false;
  int _pingFailures = 0;

  bool get isConfigured => host != null;
  bool get isConnected => status == WifiStatus.connected;

  void _set(WifiStatus s) {
    status = s;
    notifyListeners();
  }

  /// Muat perangkat tersimpan lalu cek apakah sedang online.
  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    host = p.getString(_hostKey);
    deviceName = p.getString(_nameKey);
    if (host != null) unawaited(reconnect());
  }

  /* ===== HTTP ===== */
  Future<dynamic> _get(String h, String path, {Duration timeout = const Duration(seconds: 4)}) async {
    final res = await http.get(Uri.http(h, path)).timeout(timeout);
    if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode}');
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  Future<dynamic> _post(String h, String path, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 6)}) async {
    final res = await http
        .post(Uri.http(h, path),
            headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(timeout);
    if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode}');
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  /* ===== SETUP LEWAT ACCESS POINT PERANGKAT ===== */

  /// Pastikan HP sudah tersambung ke AP perangkat. Mengembalikan nama perangkat.
  Future<String> apInfo() async {
    try {
      final info = await _get(esp8266ApHost, '/info');
      return (info is Map ? info['name'] : null)?.toString() ?? 'Swavina';
    } catch (_) {
      throw WifiException(
        'Perangkat Tidak Ditemukan',
        'Pastikan HP sudah tersambung ke WiFi "$esp8266ApSsidPrefix…" milik perangkat, lalu coba lagi.\n\n'
            'Android: jika muncul "WiFi tidak ada internet", pilih tetap terhubung atau matikan data seluler sementara.',
      );
    }
  }

  /// Daftar WiFi yang terlihat oleh perangkat. Kosong jika gagal.
  Future<List<WifiNetwork>> apScan() async {
    try {
      final res = await _get(esp8266ApHost, '/scan', timeout: const Duration(seconds: 12));
      final list = (res is Map ? res['networks'] : res) as List? ?? [];
      final seen = <String>{};
      final nets = <WifiNetwork>[];
      for (final n in list.whereType<Map>()) {
        final ssid = n['ssid']?.toString() ?? '';
        if (ssid.isEmpty || !seen.add(ssid)) continue;
        nets.add(WifiNetwork(ssid, (n['rssi'] as num?)?.toInt() ?? -100, n['secure'] != false));
      }
      nets.sort((a, b) => b.rssi.compareTo(a.rssi));
      return nets;
    } catch (_) {
      return [];
    }
  }

  /// Kirim SSID & password WiFi rumah ke perangkat.
  Future<void> apSendCredentials(String ssid, String password) async {
    try {
      await _post(esp8266ApHost, '/wifi', {'ssid': ssid, 'password': password});
    } catch (_) {
      throw WifiException('Gagal Mengirim', 'Data WiFi tidak terkirim ke perangkat. Coba lagi.');
    }
  }

  /// Tunggu perangkat terhubung ke WiFi rumah dan baca IP-nya dari `/status`.
  /// Melempar [WifiException] jika password salah / SSID tidak ditemukan.
  Future<ProvisionResult> apWaitForIp({Duration timeout = const Duration(seconds: 40)}) async {
    final end = DateTime.now().add(timeout);
    var failures = 0;
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      try {
        final s = await _get(esp8266ApHost, '/status', timeout: const Duration(seconds: 3));
        failures = 0;
        if (s is! Map) continue;
        final wifi = s['wifi']?.toString();
        if (wifi == 'connected' && (s['ip']?.toString() ?? '').isNotEmpty) {
          return ProvisionResult(ip: s['ip'].toString());
        }
        if (wifi == 'failed') {
          throw WifiException('Gagal Terhubung',
              'Perangkat tidak bisa masuk ke WiFi tersebut. Periksa nama WiFi dan password.');
        }
      } on WifiException {
        rethrow;
      } catch (_) {
        if (++failures >= 4) return ProvisionResult(lostConnection: true);
      }
    }
    return ProvisionResult(lostConnection: true);
  }

  /* ===== KONEKSI DI JARINGAN RUMAH ===== */

  /// Cari perangkat di jaringan rumah: [hintIp] → IP tersimpan → mDNS.
  Future<bool> discover({String? hintIp}) async {
    _set(WifiStatus.connecting);
    final candidates = <String>{
      if (hintIp != null && hintIp.isNotEmpty) hintIp,
      if (host != null) host!,
    };
    for (final h in candidates) {
      if (await _tryConnect(h)) return true;
    }
    final ip = await _resolveMdns();
    if (ip != null && await _tryConnect(ip)) return true;

    _set(isConfigured ? WifiStatus.disconnected : WifiStatus.idle);
    return false;
  }

  /// Hubungkan ke IP yang diketik pengguna.
  Future<void> connectManual(String ip) async {
    _set(WifiStatus.connecting);
    if (!await _tryConnect(ip.trim())) {
      _set(isConfigured ? WifiStatus.disconnected : WifiStatus.idle);
      throw WifiException('Tidak Terhubung',
          'Perangkat tidak merespons di $ip. Pastikan HP dan perangkat memakai WiFi yang sama.');
    }
  }

  /// Coba hubungkan lagi ke perangkat tersimpan.
  Future<bool> reconnect() => discover();

  Future<bool> _tryConnect(String h) async {
    try {
      final info = await _get(h, '/info');
      final name = (info is Map ? info['name'] : null)?.toString() ?? 'Swavina';
      host = h;
      deviceName = name;
      final p = await SharedPreferences.getInstance();
      await p.setString(_hostKey, h);
      await p.setString(_nameKey, name);
      _set(WifiStatus.connected);
      _startPing();
      unawaited(_ping());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _resolveMdns() async {
    // iOS/macOS: resolver sistem mendukung .local.
    try {
      final addrs = await InternetAddress.lookup(esp8266MdnsHost)
          .timeout(const Duration(seconds: 4));
      final v4 = addrs.where((a) => a.type == InternetAddressType.IPv4);
      if (v4.isNotEmpty) return v4.first.address;
    } catch (_) {}

    // Android: query mDNS langsung.
    MDnsClient? client;
    try {
      client = MDnsClient();
      await client.start();
      await for (final r in client.lookup<IPAddressResourceRecord>(
        ResourceRecordQuery.addressIPv4(esp8266MdnsHost),
        timeout: const Duration(seconds: 4),
      )) {
        return r.address.address;
      }
    } catch (e) {
      debugPrint('mDNS lookup error: $e');
    } finally {
      client?.stop();
    }
    return null;
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      _live ? const Duration(seconds: 1) : const Duration(seconds: 15),
      (_) => _ping(),
    );
  }

  /// Polling `/status` tiap detik (data sensor realtime) atau tiap 15 detik.
  void setLiveUpdates(bool on) {
    if (_live == on) return;
    _live = on;
    if (host != null) {
      _startPing();
      if (on) unawaited(_ping());
    }
  }

  /// Perbarui status perangkat; tandai terputus jika tidak merespons.
  Future<void> _ping() async {
    final h = host;
    if (h == null || _pinging) return;
    _pinging = true;
    try {
      final s = await _get(h, '/status', timeout: const Duration(seconds: 3));
      deviceStatus = _describeStatus(s);
      sensors = s is Map ? SensorSnapshot.fromJson(s['sensors']) : null;
      _pingFailures = 0;
      if (status != WifiStatus.connected) {
        _set(WifiStatus.connected);
      } else {
        notifyListeners();
      }
    } catch (_) {
      // Toleransi gangguan sesaat (polling tiap detik saat terapi).
      if (++_pingFailures < 3) return;
      deviceStatus = null;
      sensors = null;
      if (status == WifiStatus.connected) _set(WifiStatus.disconnected);
    } finally {
      _pinging = false;
    }
  }

  String? _describeStatus(dynamic s) {
    if (s is! Map) return null;
    if (s['therapy'] == 'running') {
      final left = (s['remaining'] as num?)?.toInt() ?? 0;
      final mm = (left ~/ 60).toString().padLeft(2, '0');
      final ss = (left % 60).toString().padLeft(2, '0');
      return 'Berjalan · sisa $mm:$ss';
    }
    return s['therapy'] == null ? null : 'Siap';
  }

  /* ===== PERINTAH TERAPI ===== */
  Future<void> _sendCommand(Map<String, dynamic> command) async {
    final h = host;
    if (h == null || !isConnected) {
      throw WifiException('Tidak Terhubung', 'Hubungkan perangkat terlebih dahulu.');
    }
    try {
      await _post(h, '/command', command);
    } catch (_) {
      unawaited(_ping());
      throw WifiException('Gagal Kirim', 'Perintah tidak terkirim ke perangkat lewat WiFi.');
    }
  }

  Future<void> startTherapy(int temp, int vib, int dur) =>
      _sendCommand({'cmd': 'start', 'temp': temp, 'vib': vib, 'dur': dur});

  Future<void> stopTherapy() => _sendCommand({'cmd': 'stop'});

  /// Lupakan perangkat di aplikasi (perangkat tetap memakai WiFi rumah).
  Future<void> forget() async {
    _pingTimer?.cancel();
    host = null;
    deviceName = null;
    deviceStatus = null;
    sensors = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_hostKey);
    await p.remove(_nameKey);
    _set(WifiStatus.idle);
  }

  /// Hapus WiFi tersimpan di perangkat (kembali ke mode AP) lalu lupakan.
  Future<void> resetDevice() async {
    final h = host;
    if (h != null) {
      try {
        await _post(h, '/reset', {});
      } catch (_) {}
    }
    await forget();
  }
}
