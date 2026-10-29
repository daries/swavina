import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'server_health.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Klien REST untuk backend Node.js (JWT).
///
/// Atur alamat backend saat build/run:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:3000/api
/// Default: server produksi (apiswavina.nurul-huda.net).
class Api {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://apiswavina.nurul-huda.net/api',
  );

  static const requestTimeout = Duration(seconds: 20);

  static const _tokenKey = 'AUTH_TOKEN';
  static const _loggedInKey = 'LOGGED_IN';

  static Future<String?> getToken() async =>
      (await SharedPreferences.getInstance()).getString(_tokenKey);

  /// Simpan token sekaligus menandai pengguna sudah login.
  static Future<void> saveSession(String token) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_tokenKey, token);
    await p.setString(_loggedInKey, 'true');
  }

  static Future<void> clearSession() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_tokenKey);
    await p.remove(_loggedInKey);
  }

  static Future<bool> isLoggedIn() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_loggedInKey) == 'true';
  }

  static Future<dynamic> _request(
    String method,
    String path, {
    Object? body,
  }) async {
    final token = await getToken();
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final encoded = body == null ? null : jsonEncode(body);

    late http.Response res;
    try {
      final Future<http.Response> req;
      switch (method) {
        case 'POST':
          req = http.post(uri, headers: headers, body: encoded);
          break;
        case 'PUT':
          req = http.put(uri, headers: headers, body: encoded);
          break;
        case 'DELETE':
          req = http.delete(uri, headers: headers);
          break;
        default:
          req = http.get(uri, headers: headers);
      }
      res = await req.timeout(requestTimeout);
    } catch (_) {
      ServerHealth.markOffline();
      throw ApiException('Tidak dapat terhubung ke server');
    }

    dynamic data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      data = null;
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = (data is Map && data['message'] is String)
          ? data['message'] as String
          : 'Terjadi kesalahan';
      throw ApiException(msg);
    }
    return data;
  }

  static Future<dynamic> get(String path) => _request('GET', path);
  static Future<dynamic> post(String path, Object body) =>
      _request('POST', path, body: body);
  static Future<dynamic> put(String path, Object body) =>
      _request('PUT', path, body: body);
  static Future<dynamic> delete(String path) => _request('DELETE', path);
}
