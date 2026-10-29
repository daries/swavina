import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/swavina_scaffold.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

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
    if (AppState.tabIndex.value == AppState.tabHistory) _load();
  }

  Future<void> _load() async {
    try {
      final data = await Api.get('/therapy');
      final list = (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) setState(() => _history = list);
    } on ApiException catch (e) {
      if (mounted) await showAlert(context, 'Error', e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(int id) async {
    if (!await confirmDelete(context, 'Hapus history ini?')) return;
    try {
      await Api.delete('/therapy/$id');
      if (mounted) setState(() => _history.removeWhere((h) => h['id'] == id));
    } on ApiException catch (e) {
      if (mounted) await showAlert(context, 'Error', e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return SwavinaScaffold(
      onRefresh: _load,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('History Terapi',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: c.textPrimary)),
            const SizedBox(height: 12),
            if (_loading) const Center(child: CircularProgressIndicator(color: AppColors.accent)),
            if (!_loading && _history.isEmpty)
              Text('Belum ada riwayat terapi.', style: TextStyle(color: c.textSecondary)),
            for (final item in _history)
              CardBox(
                radius: 18,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item['date']} • ${item['start_time']}',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Durasi: ${item['duration']} menit',
                        style: TextStyle(fontSize: 14, color: c.textSecondary)),
                    const SizedBox(height: 4),
                    Text('Suhu: ${item['temperature']}°C — Getar: ${item['vibration']} Hz',
                        style: TextStyle(fontSize: 14, color: c.textSecondary)),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _delete((item['id'] as num).toInt()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.deleteRed,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Hapus', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
