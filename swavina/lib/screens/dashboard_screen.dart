import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/clinical.dart';
import '../core/device_service.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/swavina_scaffold.dart';
import 'clinical_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _dashboard;
  ClinicalData? _clinical;
  String _userName = 'Pengguna';

  @override
  void initState() {
    super.initState();
    _load();
    AppState.tabIndex.addListener(_onTab);
  }

  @override
  void dispose() {
    AppState.tabIndex.removeListener(_onTab);
    super.dispose();
  }

  void _onTab() {
    if (AppState.tabIndex.value == AppState.tabHome) _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('/dashboard');
      if (mounted) setState(() => _dashboard = Map<String, dynamic>.from(d as Map));
    } catch (_) {}
    try {
      final p = await Api.get('/profile');
      final name = (p as Map)['name'];
      if (mounted && name is String && name.isNotEmpty) setState(() => _userName = name);
    } catch (_) {}
    try {
      final clinical = await ClinicalData.load();
      if (mounted) setState(() => _clinical = clinical);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final d = _dashboard;

    final todayDuration = (d?['today_duration'] as num?)?.toInt() ?? 0;
    final dailyTarget = (d?['daily_target'] as num?)?.toInt() ?? 30;
    final progress = dailyTarget == 0
        ? 0.0
        : (todayDuration / dailyTarget).clamp(0.0, 1.0).toDouble();
    final last = d?['last_session'] as Map?;

    return SwavinaScaffold(
      onRefresh: _load,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Selamat Datang, $_userName 👋',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: c.textPrimary)),
            const SizedBox(height: 2),
            Text('Terapi Hari Ini', style: TextStyle(fontSize: 16, color: c.textSecondary)),
            const SizedBox(height: 20),
            if (d == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
              )
            else ...[
              // PROGRESS HARIAN
              CardBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Progress Harian',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
                    const SizedBox(height: 8),
                    Text('$todayDuration / $dailyTarget menit',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: c.textPrimary)),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 10,
                        backgroundColor: c.progressBg,
                        valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Target Harian', style: TextStyle(fontSize: 14, color: c.textSecondary)),
                  ],
                ),
              ),

              // STATUS PERANGKAT
              ListenableBuilder(
                listenable: DeviceService.instance,
                builder: (context, _) {
                  final device = DeviceService.instance;
                  final connected = device.isConnected;
                  final color = connected ? AppColors.success : AppColors.danger;
                  return CardBox(
                    child: Row(
                      children: [
                        Icon(
                            switch (device.transport) {
                              DeviceTransport.wifi => Icons.wifi,
                              DeviceTransport.simulation => Icons.science_outlined,
                              DeviceTransport.bluetooth => Icons.bluetooth_connected,
                              null => Icons.bluetooth_disabled,
                            },
                            size: 24, color: color),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Status Perangkat',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
                            Text(connected ? 'Connected — ${device.deviceLabel}' : 'Disconnected',
                                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),

              if (_clinical?.enrolled == true) _clinicalCard(c, _clinical!),

              // TERAPI TERAKHIR
              CardBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Terapi Terakhir',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
                    const SizedBox(height: 8),
                    if (last != null) ...[
                      Text('${last['date']} • ${last['duration']} menit',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
                      const SizedBox(height: 6),
                      Text('Suhu ${last['temperature']}°C | Getar ${last['vibration']} Hz',
                          style: TextStyle(fontSize: 14, color: c.textSecondary)),
                    ] else
                      Text('Belum ada sesi terapi',
                          style: TextStyle(fontSize: 14, color: c.textSecondary)),
                  ],
                ),
              ),

              // RINGKASAN MINGGUAN
              CardBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ringkasan Mingguan',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
                    const SizedBox(height: 8),
                    _summaryRow(c, '${d['weekly_sessions'] ?? 0}', 'Sesi'),
                    _summaryRow(c, '${d['weekly_duration'] ?? 0}', 'Menit'),
                    const SizedBox(height: 6),
                    Text('Konsistensi terapi membaik ↑',
                        style: TextStyle(fontSize: 14, color: c.textSecondary)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            PrimaryButton(
              label: 'Mulai Terapi Sekarang',
              radius: 18,
              fontSize: 18,
              padding: const EdgeInsets.symmetric(vertical: 18),
              onPressed: () => AppState.tabIndex.value = AppState.tabTherapy,
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  /* ===== DATA KLINIS (hasil pemeriksaan perawat/peneliti) ===== */
  Widget _clinicalCard(AppColors c, ClinicalData d) {
    final m = d.latest;
    Widget foot(String label, double? abi) {
      final cat = abiCategory(abi);
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: c.textSecondary)),
            Text(fmtNum(abi, 2),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.textPrimary)),
            if (cat != null)
              Text(cat.label, style: TextStyle(fontWeight: FontWeight.w700, color: toneColor(cat.tone, c))),
          ],
        ),
      );
    }

    return CardBox(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ClinicalScreen(initial: d)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Data Klinis',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
              ),
              if (d.offline) Icon(Icons.cloud_off, size: 16, color: c.textSecondary),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: c.textSecondary),
            ],
          ),
          const SizedBox(height: 2),
          if (m == null)
            Text('Belum ada hasil pemeriksaan dari Puskesmas.',
                style: TextStyle(fontSize: 14, color: c.textSecondary))
          else ...[
            Text('Vaskularisasi kaki (ABI) · ${fmtDate(m.measuredAt)}',
                style: TextStyle(fontSize: 13, color: c.textSecondary)),
            const SizedBox(height: 10),
            Row(children: [foot('Kaki kiri', m.abiLeft), foot('Kaki kanan', m.abiRight)]),
            const SizedBox(height: 8),
            const Text('Lihat gejala saraf, nyeri, suhu kulit, dan perkembangan →',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accent)),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(AppColors c, String value, String label) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: c.textPrimary)),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 16, color: c.textSecondary)),
      ],
    );
  }
}
