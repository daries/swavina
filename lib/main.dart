import 'package:flutter/material.dart';

import 'core/api.dart';
import 'core/theme.dart';
import 'core/wifi_service.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  WifiService.instance.init();
  runApp(const SwavinaApp());
}

class SwavinaApp extends StatelessWidget {
  const SwavinaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Swavina',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const AuthGate(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/home': (_) => const HomeShell(),
      },
    );
  }
}

/// Menentukan layar awal: Home jika sudah login, Login jika belum.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: Api.isLoggedIn(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snap.data == true ? const HomeShell() : const LoginScreen();
      },
    );
  }
}
