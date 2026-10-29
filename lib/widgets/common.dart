import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Kartu dengan bayangan lembut (setara style `card` di versi Expo).
class CardBox extends StatelessWidget {
  const CardBox({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = const EdgeInsets.all(20),
    this.margin = const EdgeInsets.only(bottom: 16),
    this.color,
    this.onTap,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final box = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      child: child,
    );
    return onTap == null ? box : GestureDetector(onTap: onTap, child: box);
  }
}

/// Tombol besar berwarna penuh.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.accent,
    this.radius = 16,
    this.fontSize = 17,
    this.padding = const EdgeInsets.symmetric(vertical: 16),
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final double radius;
  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: onPressed == null ? const Color(0xFFAAAAAA) : color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFAAAAAA),
          disabledForegroundColor: Colors.white,
          padding: padding,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

Future<void> showAlert(BuildContext context, String title, String message) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}

/// Dialog konfirmasi Batal / Hapus. Mengembalikan true jika dikonfirmasi.
Future<bool> confirmDelete(BuildContext context, String message) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Konfirmasi'),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
      ],
    ),
  );
  return res ?? false;
}
