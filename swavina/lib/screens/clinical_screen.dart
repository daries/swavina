import 'package:flutter/material.dart';

import '../core/clinical.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

Color toneColor(Tone t, AppColors c) => switch (t) {
      Tone.good => AppColors.success,
      Tone.warn => AppColors.warning,
      Tone.bad => AppColors.danger,
      Tone.neutral => c.textSecondary,
    };

/// Data klinis read-only: hasil pemeriksaan perawat/peneliti di Puskesmas.
class ClinicalScreen extends StatefulWidget {
  const ClinicalScreen({super.key, this.initial});

  final ClinicalData? initial;

  @override
  State<ClinicalScreen> createState() => _ClinicalScreenState();
}

class _ClinicalScreenState extends State<ClinicalScreen> {
  ClinicalData? _data;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _data = widget.initial;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await ClinicalData.load();
      if (mounted) setState(() => (_data = d, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final d = _data;

    return Scaffold(
      appBar: AppBar(title: const Text('Data Klinis'), backgroundColor: c.pageBg),
      backgroundColor: c.pageBg,
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (d == null && _loading)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
              )
            else if (d == null)
              _message(c, Icons.cloud_off, 'Data klinis belum bisa dimuat',
                  _error ?? 'Periksa koneksi internet lalu tarik ke bawah untuk mencoba lagi.')
            else if (!d.enrolled)
              _message(c, Icons.assignment_ind_outlined, 'Belum terdaftar sebagai responden',
                  'Data klinis akan tampil setelah perawat/peneliti menghubungkan akun ini dengan data penelitian Anda.')
            else ...[
              _header(c, d),
              _profileCard(c, d),
              if (d.measurements.isEmpty)
                CardBox(
                  child: _message(c, Icons.event_note, 'Belum ada hasil pemeriksaan',
                      'Hasil pemeriksaan (ABI, gejala saraf, nyeri, suhu kulit, laktat) akan muncul setelah kunjungan pengukuran di Puskesmas.',
                      top: 8),
                )
              else ...[
                _abiCard(c, d),
                _comparisonCard(c, d),
                _historyCard(c, d),
              ],
              if (d.adverseEvents.isNotEmpty) _safetyCard(c, d),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 20),
                child: Text(
                  'Data ini diinput oleh perawat/peneliti dan hanya dapat dibaca. '
                  'Diskusikan hasil pemeriksaan dengan tenaga kesehatan Anda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.5, color: c.textSecondary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _message(AppColors c, IconData icon, String title, String body, {double top = 40}) => Padding(
        padding: EdgeInsets.only(top: top),
        child: Column(
          children: [
            Icon(icon, size: 48, color: c.textSecondary),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: TextStyle(height: 1.5, color: c.textSecondary)),
          ],
        ),
      );

  Widget _header(AppColors c, ClinicalData d) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Responden ${d.code ?? ''}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary)),
                  Text(
                      d.latest == null
                          ? 'Belum ada pemeriksaan'
                          : 'Pemeriksaan terakhir ${fmtDate(d.latest!.measuredAt)}',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
                ],
              ),
            ),
            if (d.offline)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, size: 14, color: AppColors.warning),
                    SizedBox(width: 4),
                    Text('Offline',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.warning)),
                  ],
                ),
              ),
          ],
        ),
      );

  /* ===== DATA RESPONDEN (INPUT PERAWAT/PENELITI) ===== */
  Widget _profileCard(AppColors c, ClinicalData d) {
    final p = d.participant!;
    final study = <(String, String)>[
      ('Kelompok', d.group == 'kontrol' ? 'Kontrol' : 'Intervensi'),
      if (p['study_start'] != null) ('Mulai penelitian', fmtDate(p['study_start'].toString())),
      if (p['planned_sessions'] != null) ('Sesi direncanakan', '${p['planned_sessions']} sesi'),
      if (p['status'] != null)
        ('Status', const {
              'aktif': 'Aktif',
              'selesai': 'Selesai',
              'drop_out': 'Berhenti',
              'menunggu': 'Menunggu persetujuan',
              'ditolak': 'Ditolak',
            }[p['status']] ?? '${p['status']}'),
    ];
    final traits = d.characteristics;

    Widget row((String, String) kv) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(kv.$1, style: TextStyle(color: c.textSecondary))),
              const SizedBox(width: 12),
              Flexible(
                child: Text(kv.$2,
                    textAlign: TextAlign.end,
                    style: TextStyle(fontWeight: FontWeight.w600, color: c.textPrimary)),
              ),
            ],
          ),
        );

    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Data Responden',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
          const SizedBox(height: 4),
          Text('Dicatat oleh perawat/peneliti saat pendaftaran penelitian.',
              style: TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary)),
          const SizedBox(height: 8),
          for (final kv in study) row(kv),
          if (traits.isNotEmpty) ...[
            Divider(height: 20, color: c.border),
            Text('Kondisi Kesehatan',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.textPrimary)),
            const SizedBox(height: 4),
            for (final kv in traits) row(kv),
          ],
        ],
      ),
    );
  }

  /* ===== CATATAN KEAMANAN ===== */
  Widget _safetyCard(AppColors c, ClinicalData d) {
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Catatan Keamanan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
          const SizedBox(height: 4),
          Text('Keluhan selama terapi yang dicatat perawat beserta tindak lanjutnya.',
              style: TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary)),
          for (final e in d.adverseEvents)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.cardAlt, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(fmtDate(e.occurredAt),
                            style: TextStyle(fontWeight: FontWeight.w700, color: c.textPrimary)),
                      ),
                      Text(e.severityLabel,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: toneColor(e.tone, c))),
                    ],
                  ),
                  if (e.types.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(e.types.join(', '), style: TextStyle(color: c.textPrimary)),
                    ),
                  if (e.description != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(e.description!, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                    ),
                  if (e.actionTaken != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Tindakan: ${e.actionTaken}',
                          style: TextStyle(fontSize: 13, color: c.textSecondary)),
                    ),
                  if (e.stopped)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Terapi dihentikan',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.danger)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /* ===== MONITORING VASKULARISASI KAKI (ABI) ===== */
  Widget _abiCard(AppColors c, ClinicalData d) {
    final m = d.latest!;
    final base = d.baseline;
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vaskularisasi Kaki (ABI)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
          const SizedBox(height: 4),
          Text('Ankle-Brachial Index menunjukkan kecukupan aliran darah ke kaki.',
              style: TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _abiFoot(c, 'Kaki kiri', m.abiLeft, base == m ? null : base?.abiLeft)),
              const SizedBox(width: 10),
              Expanded(child: _abiFoot(c, 'Kaki kanan', m.abiRight, base == m ? null : base?.abiRight)),
            ],
          ),
          const SizedBox(height: 16),
          AbiScale(left: m.abiLeft, right: m.abiRight),
        ],
      ),
    );
  }

  Widget _abiFoot(AppColors c, String label, double? abi, double? before) {
    final cat = abiCategory(abi);
    final color = cat == null ? c.textSecondary : toneColor(cat.tone, c);
    final delta = abi != null && before != null ? abi - before : null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.cardAlt, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: c.textSecondary)),
          const SizedBox(height: 4),
          Text(fmtNum(abi, 2),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
          if (cat != null) Text(cat.label, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          if (delta != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${delta >= 0 ? '▲' : '▼'} ${fmtNum(delta.abs(), 2)} dari awal',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: delta == 0 ? c.textSecondary : (delta > 0 ? AppColors.success : AppColors.danger),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /* ===== PERBANDINGAN AWAL VS TERAKHIR ===== */
  Widget _comparisonCard(AppColors c, ClinicalData d) {
    final base = d.baseline!;
    final last = d.latest!;
    final same = identical(base, last);
    final rows = outcomes.where((o) => base.value(o.key) != null || last.value(o.key) != null).toList();

    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(same ? 'Hasil Pemeriksaan' : 'Perkembangan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
          if (!same)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${fmtDate(base.measuredAt)} → ${fmtDate(last.measuredAt)}',
                  style: TextStyle(fontSize: 13, color: c.textSecondary)),
            ),
          const SizedBox(height: 6),
          for (final o in rows) _outcomeRow(c, o, same ? null : base.value(o.key), last.value(o.key)),
        ],
      ),
    );
  }

  Widget _outcomeRow(AppColors c, Outcome o, double? before, double? now) {
    final delta = before != null && now != null ? now - before : null;
    Color? deltaColor;
    if (delta != null && delta.abs() > 1e-9 && o.better != 0) {
      deltaColor = (delta > 0) == (o.better > 0) ? AppColors.success : AppColors.danger;
    }
    final extra = o.key == 'nrs' ? nrsCategory(now) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.label, style: TextStyle(fontWeight: FontWeight.w600, color: c.textPrimary)),
                const SizedBox(height: 2),
                Text(o.explain, style: TextStyle(fontSize: 12, height: 1.4, color: c.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text.rich(
                  textAlign: TextAlign.end,
                  TextSpan(children: [
                    if (before != null)
                      TextSpan(text: '${fmtNum(before, o.digits)} → ', style: TextStyle(color: c.textSecondary)),
                    TextSpan(
                      text: fmtNum(now, o.digits),
                      style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
                    ),
                    if (o.unit.isNotEmpty)
                      TextSpan(text: ' ${o.unit}', style: TextStyle(fontSize: 12, color: c.textSecondary)),
                  ]),
                  style: const TextStyle(fontSize: 16, fontFeatures: [FontFeature.tabularFigures()]),
                ),
                if (deltaColor != null)
                  Text(
                    deltaColor == AppColors.success ? 'Membaik' : 'Perlu perhatian',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: deltaColor),
                  )
                else if (extra != null)
                  Text(extra.label,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: toneColor(extra.tone, c))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /* ===== RIWAYAT KUNJUNGAN ===== */
  Widget _historyCard(AppColors c, ClinicalData d) {
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Riwayat Pemeriksaan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
          const SizedBox(height: 6),
          for (final m in d.measurements.reversed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.medical_information_outlined, color: AppColors.accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m.timepointLabel} · ${fmtDate(m.measuredAt)}',
                            style: TextStyle(fontWeight: FontWeight.w600, color: c.textPrimary)),
                        Text(
                          [
                            if (m.abiLeft != null || m.abiRight != null)
                              'ABI ${fmtNum(m.abiLeft, 2)} / ${fmtNum(m.abiRight, 2)}',
                            if (m.nrs != null) 'Nyeri ${fmtNum(m.nrs, 0)}/10',
                            if (m.skinLeft != null) 'Suhu ${fmtNum(m.skinLeft, 1)} / ${fmtNum(m.skinRight, 1)}°C',
                          ].join(' · '),
                          style: TextStyle(fontSize: 13, color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Skala ABI berwarna (0,5–1,5) dengan penanda kaki kiri (K) & kanan (Ka).
class AbiScale extends StatelessWidget {
  const AbiScale({super.key, this.left, this.right});

  final double? left;
  final double? right;

  static const _min = 0.5;
  static const _max = 1.5;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    double pos(double v) => ((v.clamp(_min, _max) - _min) / (_max - _min));
    // Zona: abnormal ≤0,90 · borderline 0,91–0,99 · normal 1,00–1,40 · kaku >1,40
    final zones = [
      (from: _min, to: 0.90, color: AppColors.danger),
      (from: 0.90, to: 1.00, color: AppColors.warning),
      (from: 1.00, to: 1.40, color: AppColors.success),
      (from: 1.40, to: _max, color: AppColors.warning),
    ];

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      Widget marker(double v, String label) => Positioned(
            left: (pos(v) * w - 14).clamp(0, w - 28),
            top: 0,
            child: Column(
              children: [
                Container(
                  width: 28,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(color: c.textPrimary, borderRadius: BorderRadius.circular(6)),
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c.card)),
                ),
                Container(width: 2, height: 16, color: c.textPrimary),
              ],
            ),
          );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 50,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 30,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      children: [
                        for (final z in zones)
                          Expanded(
                            flex: ((z.to - z.from) * 100).round(),
                            child: Container(height: 10, color: z.color.withValues(alpha: 0.75)),
                          ),
                      ],
                    ),
                  ),
                ),
                if (left != null) marker(left!, 'K'),
                if (right != null) marker(right!, 'Ka'),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            runSpacing: 4,
            children: [
              _legend(c, AppColors.danger, '≤ 0,90 abnormal'),
              _legend(c, AppColors.warning, '0,91–0,99'),
              _legend(c, AppColors.success, '1,00–1,40 normal'),
            ],
          ),
        ],
      );
    });
  }

  Widget _legend(AppColors c, Color color, String text) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(fontSize: 11, color: c.textSecondary)),
          ],
        ),
      );
}
