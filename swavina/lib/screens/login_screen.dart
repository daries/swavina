import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/server_status_badge.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      await showAlert(context, 'Error', 'Email dan password wajib diisi');
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await Api.post('/auth/login', {'email': email, 'password': password});
      await Api.saveSession(res['token'] as String);
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    } on ApiException catch (e) {
      if (mounted) await showAlert(context, 'Login Gagal', e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    Widget field({
      required IconData icon,
      required String hint,
      required TextEditingController controller,
      bool obscure = false,
      TextInputType? keyboard,
    }) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: obscure,
                keyboardType: keyboard,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                style: TextStyle(fontSize: 16, color: c.textPrimary),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(color: c.textSecondary),
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.pageBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: ServerStatusBadge()),
                const SizedBox(height: 12),
                Center(
                  child: Image.asset('assets/images/logo_swavina.png', width: 120, height: 120),
                ),
                const SizedBox(height: 20),
                Text('Masuk ke Swavina',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: c.textPrimary)),
                const SizedBox(height: 6),
                Text('Silakan login untuk melanjutkan terapi Anda',
                    style: TextStyle(fontSize: 15, color: c.textSecondary)),
                const SizedBox(height: 26),
                field(
                  icon: Icons.mail_outline,
                  hint: 'Email',
                  controller: _email,
                  keyboard: TextInputType.emailAddress,
                ),
                field(
                  icon: Icons.lock_outline,
                  hint: 'Password',
                  controller: _password,
                  obscure: true,
                ),
                const SizedBox(height: 10),
                PrimaryButton(
                  label: _loading ? 'Memuat...' : 'Masuk',
                  onPressed: _loading ? null : _login,
                  radius: 14,
                ),
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pushNamed('/register'),
                    child: const Text('Belum punya akun? Daftar',
                        style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
