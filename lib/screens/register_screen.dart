import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/server_status_badge.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      await showAlert(context, 'Error', 'Semua field wajib diisi');
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await Api.post(
        '/auth/register',
        {'name': name, 'email': email, 'password': password},
      );
      await Api.saveSession(res['token'] as String);
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    } on ApiException catch (e) {
      if (mounted) await showAlert(context, 'Registrasi Gagal', e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: c.textSecondary),
          contentPadding: const EdgeInsets.all(14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: c.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.accent),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Register'),
        backgroundColor: c.pageBg,
        actions: const [
          Padding(padding: EdgeInsets.only(right: 12), child: ServerStatusBadge()),
        ],
      ),
      backgroundColor: c.pageBg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text('Register Akun',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: c.textPrimary)),
              const SizedBox(height: 20),
              CardBox(
                child: Column(
                  children: [
                    TextField(
                      controller: _name,
                      style: TextStyle(color: c.textPrimary, fontSize: 16),
                      decoration: deco('Nama Lengkap'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      style: TextStyle(color: c.textPrimary, fontSize: 16),
                      decoration: deco('Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      style: TextStyle(color: c.textPrimary, fontSize: 16),
                      decoration: deco('Password'),
                    ),
                    const SizedBox(height: 16),
                    PrimaryButton(
                      label: _loading ? 'Memuat...' : 'Register',
                      onPressed: _loading ? null : _register,
                      color: AppColors.success,
                      fontSize: 18,
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Text('Kembali ke Login',
                          style: TextStyle(fontSize: 15, color: c.textSecondary)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
