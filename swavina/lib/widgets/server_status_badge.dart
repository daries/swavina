import 'package:flutter/material.dart';

import '../core/server_health.dart';
import '../core/theme.dart';

/// Penanda status backend (online / offline). Ketuk untuk cek ulang.
class ServerStatusBadge extends StatefulWidget {
  const ServerStatusBadge({super.key});

  @override
  State<ServerStatusBadge> createState() => _ServerStatusBadgeState();
}

class _ServerStatusBadgeState extends State<ServerStatusBadge> {
  @override
  void initState() {
    super.initState();
    ServerHealth.watch();
  }

  @override
  void dispose() {
    ServerHealth.unwatch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ValueListenableBuilder<ServerStatus>(
      valueListenable: ServerHealth.status,
      builder: (context, status, _) {
        final (color, label) = switch (status) {
          ServerStatus.online => (AppColors.success, 'Server online'),
          ServerStatus.offline => (AppColors.danger, 'Server offline'),
          ServerStatus.checking => (AppColors.warning, 'Memeriksa server...'),
        };
        return GestureDetector(
          onTap: ServerHealth.check,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: c.card.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary)),
              ],
            ),
          ),
        );
      },
    );
  }
}
