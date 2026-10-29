import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api.dart';

enum ServerStatus { checking, online, offline }

/// Health check backend: `GET {baseUrl}/` berkala selama ada widget yang memantau.
class ServerHealth {
  ServerHealth._();

  static final status = ValueNotifier<ServerStatus>(ServerStatus.checking);

  static const interval = Duration(seconds: 15);
  static const timeout = Duration(seconds: 6);

  static Timer? _timer;
  static int _watchers = 0;
  static bool _busy = false;

  static Future<void> check() async {
    if (_busy) return;
    _busy = true;
    try {
      final res = await http.get(Uri.parse('${Api.baseUrl}/')).timeout(timeout);
      status.value = res.statusCode == 200 ? ServerStatus.online : ServerStatus.offline;
    } catch (_) {
      status.value = ServerStatus.offline;
    } finally {
      _busy = false;
    }
  }

  static void markOffline() => status.value = ServerStatus.offline;

  static void watch() {
    if (_watchers++ > 0) return;
    check();
    _timer = Timer.periodic(interval, (_) => check());
  }

  static void unwatch() {
    if (--_watchers > 0) return;
    _timer?.cancel();
    _timer = null;
  }
}
