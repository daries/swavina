import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Hasil pengukuran klinis yang diinput perawat/peneliti (read-only di app pasien).
class ClinicalMeasurement {
  ClinicalMeasurement(this.json);
  final Map<String, dynamic> json;

  double? _d(String k) => (json[k] as num?)?.toDouble();

  String get timepoint => json['timepoint']?.toString() ?? 'lainnya';
  String get measuredAt => json['measured_at']?.toString() ?? '';
  double? get abiLeft => _d('abi_left');
  double? get abiRight => _d('abi_right');
  double? get ntss6 => _d('ntss6_total');
  double? get dn4 => _d('dn4_total');
  double? get nrs => _d('nrs');
  double? get skinLeft => _d('skin_temp_left');
  double? get skinRight => _d('skin_temp_right');
  double? get lactate => _d('lactate');

  double? value(String key) => _d(key);

  String get timepointLabel => switch (timepoint) {
        'pre' => 'Awal (pre-test)',
        'post' => 'Akhir (post-test)',
        _ => 'Pemeriksaan',
      };
}

/// Formulir keamanan / kejadian tidak diinginkan yang dicatat perawat.
class AdverseEvent {
  AdverseEvent(this.json);
  final Map<String, dynamic> json;

  String get occurredAt => json['occurred_at']?.toString() ?? '';
  String get severity => json['severity']?.toString() ?? 'ringan';
  String? get description => _text(json['description']);
  String? get actionTaken => _text(json['action_taken']);
  bool get stopped => json['decision'] == 'hentikan';
  List<String> get types => (json['types'] as List? ?? []).map((t) => aeTypeLabels[t] ?? '$t').toList();

  String get severityLabel => switch (severity) { 'berat' => 'Berat', 'sedang' => 'Sedang', _ => 'Ringan' };
  Tone get tone => switch (severity) { 'berat' => Tone.bad, 'sedang' => Tone.warn, _ => Tone.neutral };
}

const aeTypeLabels = {
  'kemerahan': 'Kemerahan',
  'rasa_panas_berlebih': 'Rasa panas berlebihan',
  'iritasi': 'Iritasi',
  'luka_bakar': 'Luka bakar',
  'peningkatan_nyeri': 'Peningkatan nyeri',
  'pusing': 'Pusing',
  'gangguan_perangkat': 'Gangguan perangkat',
  'lainnya': 'Lainnya',
};

String? _text(dynamic v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

/// Data klinis peserta + waktu terakhir diperbarui dari server.
class ClinicalData {
  ClinicalData({
    required this.participant,
    required this.measurements,
    required this.updatedAt,
    this.adverseEvents = const [],
    this.offline = false,
  });

  final Map<String, dynamic>? participant;
  final List<ClinicalMeasurement> measurements; // urut tanggal naik
  final List<AdverseEvent> adverseEvents; // terbaru dulu
  final DateTime updatedAt;
  final bool offline;

  bool get enrolled => participant != null;
  String? get code => participant?['code']?.toString();
  String? get group => participant?['group_type']?.toString();

  double? _num(String k) => (participant?[k] as num?)?.toDouble();

  /// Karakteristik responden yang diinput perawat/peneliti (label, nilai);
  /// kolom yang belum diisi dilewati.
  List<(String, String)> get characteristics {
    final birth = DateTime.tryParse(participant?['birth_date']?.toString() ?? '');
    int? age;
    if (birth != null) {
      final now = DateTime.now();
      age = now.year - birth.year - (DateTime(now.year, birth.month, birth.day).isAfter(now) ? 1 : 0);
    }
    final h = _num('height'), w = _num('weight');
    final bmi = h != null && w != null && h > 0 ? w / ((h / 100) * (h / 100)) : null;
    final sys = _num('systolic'), dia = _num('diastolic');
    const smoking = {'tidak': 'Tidak', 'mantan': 'Mantan perokok', 'ya': 'Ya'};
    const activity = {'rendah': 'Rendah', 'sedang': 'Sedang', 'tinggi': 'Tinggi'};
    final rows = <(String, String?)>[
      ('Usia', age == null ? null : '$age tahun'),
      ('Jenis kelamin', const {'L': 'Laki-laki', 'P': 'Perempuan'}[participant?['sex']]),
      ('Lama diabetes', _num('dm_duration_years') == null ? null : '${fmtNum(_num('dm_duration_years'), 1)} tahun'),
      ('HbA1c', _num('hba1c') == null ? null : '${fmtNum(_num('hba1c'), 1)}%'),
      ('Gula darah', _num('blood_glucose') == null ? null : '${fmtNum(_num('blood_glucose'), 0)} mg/dL'),
      ('Tekanan darah', sys == null ? null : '${fmtNum(sys, 0)}/${dia == null ? '-' : fmtNum(dia, 0)} mmHg'),
      ('Tinggi badan', h == null ? null : '${fmtNum(h, 1)} cm'),
      ('Berat badan', w == null ? null : '${fmtNum(w, 1)} kg'),
      ('IMT', bmi == null ? null : '${fmtNum(bmi, 1)} kg/m²'),
      ('Merokok', smoking[participant?['smoking']] ?? _text(participant?['smoking'])),
      ('Aktivitas fisik', activity[participant?['physical_activity']] ?? _text(participant?['physical_activity'])),
      ('Penyakit penyerta', _text(participant?['comorbidities'])),
      ('Obat diabetes', _text(participant?['antidiabetic'])),
      ('Obat nyeri', _text(participant?['analgesic'])),
      ('Obat neuropati', _text(participant?['neuropathy_drug'])),
    ];
    return [for (final (k, v) in rows) if (v != null) (k, v)];
  }

  ClinicalMeasurement? get latest => measurements.isEmpty ? null : measurements.last;

  ClinicalMeasurement? get baseline {
    for (final m in measurements) {
      if (m.timepoint == 'pre') return m;
    }
    return measurements.isEmpty ? null : measurements.first;
  }

  static ClinicalData _fromJson(Map<String, dynamic> j, DateTime updatedAt, {bool offline = false}) {
    final list = (j['measurements'] as List? ?? [])
        .whereType<Map>()
        .map((m) => ClinicalMeasurement(Map<String, dynamic>.from(m)))
        .toList()
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    return ClinicalData(
      participant: j['participant'] is Map ? Map<String, dynamic>.from(j['participant'] as Map) : null,
      measurements: list,
      adverseEvents: (j['adverse_events'] as List? ?? [])
          .whereType<Map>()
          .map((e) => AdverseEvent(Map<String, dynamic>.from(e)))
          .toList(),
      updatedAt: updatedAt,
      offline: offline,
    );
  }

  static const _cacheKey = 'CLINICAL_CACHE';
  static const _cacheTimeKey = 'CLINICAL_CACHE_TIME';

  /// Tarik dari server; jika offline pakai cache lokal terakhir.
  static Future<ClinicalData?> load() async {
    final p = await SharedPreferences.getInstance();
    try {
      final j = Map<String, dynamic>.from(await Api.get('/clinical') as Map);
      final now = DateTime.now();
      await p.setString(_cacheKey, jsonEncode(j));
      await p.setString(_cacheTimeKey, now.toIso8601String());
      return _fromJson(j, now);
    } catch (_) {
      final raw = p.getString(_cacheKey);
      if (raw == null) rethrow;
      final time = DateTime.tryParse(p.getString(_cacheTimeKey) ?? '') ?? DateTime.now();
      return _fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map), time, offline: true);
    }
  }

  static Future<void> clearCache() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_cacheKey);
    await p.remove(_cacheTimeKey);
  }
}

enum Tone { good, warn, bad, neutral }

/// Kategori ABI (proposal Tabel 3.2).
({String label, Tone tone, String hint})? abiCategory(double? abi) {
  if (abi == null) return null;
  if (abi <= 0.90) {
    return (label: 'Abnormal', tone: Tone.bad, hint: 'Aliran darah ke kaki berkurang');
  }
  if (abi < 1.0) {
    return (label: 'Borderline', tone: Tone.warn, hint: 'Sedikit di bawah normal');
  }
  if (abi <= 1.40) {
    return (label: 'Normal', tone: Tone.good, hint: 'Aliran darah ke kaki baik');
  }
  return (label: 'Arteri kaku', tone: Tone.warn, hint: 'Pembuluh sulit ditekan, perlu evaluasi');
}

({String label, Tone tone})? nrsCategory(double? n) {
  if (n == null) return null;
  if (n == 0) return (label: 'Tidak nyeri', tone: Tone.good);
  if (n <= 3) return (label: 'Nyeri ringan', tone: Tone.good);
  if (n <= 6) return (label: 'Nyeri sedang', tone: Tone.warn);
  return (label: 'Nyeri berat', tone: Tone.bad);
}

/// Outcome yang ditampilkan ke pasien dengan penjelasan sederhana.
class Outcome {
  const Outcome(this.key, this.label, this.unit, this.digits, this.better, this.explain);
  final String key;
  final String label;
  final String unit;
  final int digits;

  /// 1 = makin tinggi makin baik, -1 = makin rendah makin baik, 0 = netral.
  final int better;
  final String explain;
}

const outcomes = <Outcome>[
  Outcome('abi_left', 'ABI kaki kiri', '', 2, 1, 'Perbandingan tekanan darah kaki dan lengan. Normal 1,00–1,40.'),
  Outcome('abi_right', 'ABI kaki kanan', '', 2, 1, 'Perbandingan tekanan darah kaki dan lengan. Normal 1,00–1,40.'),
  Outcome('ntss6_total', 'Gejala saraf (NTSS-6)', '', 2, -1, 'Skor baal, kesemutan, rasa terbakar, dan nyeri. Makin rendah makin baik.'),
  Outcome('nrs', 'Nyeri kaki (NRS)', '/10', 0, -1, 'Skala nyeri 0 (tidak nyeri) sampai 10 (terberat).'),
  Outcome('dn4_total', 'Nyeri saraf (DN4)', '/10', 0, -1, 'Skor ≥ 4 menandakan nyeri bersifat neuropatik.'),
  Outcome('skin_temp_left', 'Suhu kulit kaki kiri', '°C', 1, 0, 'Diukur dengan termometer inframerah.'),
  Outcome('skin_temp_right', 'Suhu kulit kaki kanan', '°C', 1, 0, 'Diukur dengan termometer inframerah.'),
  Outcome('lactate', 'Laktat darah', 'mmol/L', 2, -1, 'Penanda metabolisme jaringan. Penurunan umumnya baik.'),
];

String fmtNum(double? v, int digits) {
  if (v == null) return '-';
  final s = v.toStringAsFixed(digits);
  return s.replaceAll('.', ',');
}

String fmtDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
