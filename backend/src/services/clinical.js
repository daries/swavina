// Perhitungan instrumen klinis sesuai proposal Tahap III.

const round = (v, d = 2) => (v == null || Number.isNaN(v) ? null : Math.round(v * 10 ** d) / 10 ** d);
const num = (v) => (v === "" || v == null || Number.isNaN(Number(v)) ? null : Number(v));

/**
 * ABI per tungkai = tekanan sistolik tertinggi pergelangan kaki (dorsalis pedis /
 * tibialis posterior) sisi tsb ÷ tekanan sistolik brakialis tertinggi (kiri/kanan).
 */
function computeAbi({ brachial_left, brachial_right, dp_left, pt_left, dp_right, pt_right }) {
  const brachial = Math.max(num(brachial_left) ?? 0, num(brachial_right) ?? 0);
  const ankle = (a, b) => Math.max(num(a) ?? 0, num(b) ?? 0);
  if (!brachial) return { abi_left: null, abi_right: null };
  const l = ankle(dp_left, pt_left);
  const r = ankle(dp_right, pt_right);
  return { abi_left: l ? round(l / brachial) : null, abi_right: r ? round(r / brachial) : null };
}

function abiCategory(abi) {
  if (abi == null) return null;
  if (abi <= 0.9) return "abnormal";
  if (abi < 1.0) return "borderline";
  if (abi <= 1.4) return "normal";
  return "tidak terkompresi";
}

/**
 * NTSS-6: 6 gejala, tiap gejala dinilai frekuensi (0 tidak ada, 1 kadang, 2 sering,
 * 3 terus-menerus) × intensitas (1 ringan, 2 sedang, 3 berat). Total 0–21,96.
 */
const NTSS6_SYMPTOMS = [
  "baal",
  "kesemutan",
  "rasa_terbakar",
  "nyeri_tumpul",
  "nyeri_tajam",
  "alodinia",
];
const NTSS6_MATRIX = {
  1: { 1: 1.0, 2: 2.0, 3: 3.0 },
  2: { 1: 1.33, 2: 2.33, 3: 3.33 },
  3: { 1: 1.66, 2: 2.66, 3: 3.66 },
};

function computeNtss6(items) {
  if (!items || typeof items !== "object") return null;
  let total = 0;
  let any = false;
  for (const key of NTSS6_SYMPTOMS) {
    const it = items[key];
    if (!it) continue;
    any = true;
    const f = Number(it.freq);
    const i = Number(it.intensity);
    if (f > 0 && NTSS6_MATRIX[f]?.[i]) total += NTSS6_MATRIX[f][i];
  }
  return any ? round(total) : null;
}

/** DN4: 10 item ya/tidak; skor ≥ 4 = kemungkinan nyeri neuropatik. */
function computeDn4(items) {
  if (!Array.isArray(items) || !items.length) return null;
  return items.filter(Boolean).length;
}

/**
 * Kepatuhan = sesi selesai ÷ sesi direncanakan × 100%. Sesi dihitung sejak
 * study_start (jika ada). Sesi yang dihentikan sebelum target tidak dihitung.
 */
function compliance(db, participant) {
  if (!participant.user_id) {
    return { sessions: 0, completed: 0, stopped: 0, planned: participant.planned_sessions, percent: null, last_session: null };
  }
  const since = participant.study_start || "0000-00-00";
  const row = db
    .prepare(
      `SELECT COUNT(*) AS sessions,
              SUM(CASE WHEN COALESCE(status, 'completed') = 'completed' THEN 1 ELSE 0 END) AS completed,
              SUM(CASE WHEN status = 'stopped' THEN 1 ELSE 0 END) AS stopped,
              MAX(date || ' ' || COALESCE(start_time, '')) AS last_session
       FROM therapy_history WHERE user_id = ? AND date >= ?`
    )
    .get(participant.user_id, since);
  const planned = participant.planned_sessions || 28;
  const completed = row.completed || 0;
  return {
    sessions: row.sessions || 0,
    completed,
    stopped: row.stopped || 0,
    planned,
    percent: round(Math.min(100, (completed / planned) * 100), 1),
    last_session: row.last_session ? row.last_session.trim() : null,
  };
}

/** Normalisasi body pengukuran + hitung skor turunan. */
function normalizeMeasurement(body) {
  const m = {
    timepoint: body.timepoint,
    measured_at: body.measured_at,
    brachial_left: num(body.brachial_left),
    brachial_right: num(body.brachial_right),
    dp_left: num(body.dp_left),
    pt_left: num(body.pt_left),
    dp_right: num(body.dp_right),
    pt_right: num(body.pt_right),
    nrs: num(body.nrs),
    skin_temp_left: num(body.skin_temp_left),
    skin_temp_right: num(body.skin_temp_right),
    skin_temp_points: body.skin_temp_points ? JSON.stringify(body.skin_temp_points) : null,
    room_temp: num(body.room_temp),
    lactate: num(body.lactate),
    notes: body.notes || null,
    ntss6_items: body.ntss6_items ? JSON.stringify(body.ntss6_items) : null,
    ntss6_total: computeNtss6(body.ntss6_items),
    dn4_items: body.dn4_items ? JSON.stringify(body.dn4_items) : null,
    dn4_total: computeDn4(body.dn4_items),
  };
  // ABI dihitung dari tekanan; jika tekanan kosong, pakai nilai ABI yang diinput langsung.
  const abi = computeAbi(m);
  m.abi_left = abi.abi_left ?? num(body.abi_left);
  m.abi_right = abi.abi_right ?? num(body.abi_right);

  // Suhu kulit per kaki = rerata titik-titik pengukuran bila diisi per titik.
  const pts = body.skin_temp_points;
  if (pts && typeof pts === "object") {
    const mean = (side) => {
      const vals = Object.values(pts[side] || {}).map(num).filter((v) => v != null);
      return vals.length ? round(vals.reduce((a, b) => a + b, 0) / vals.length) : null;
    };
    m.skin_temp_left = mean("left") ?? m.skin_temp_left;
    m.skin_temp_right = mean("right") ?? m.skin_temp_right;
  }
  return m;
}

/** Parse kolom JSON saat dikirim ke klien. */
function parseMeasurement(row) {
  if (!row) return row;
  const parse = (v) => {
    try {
      return v ? JSON.parse(v) : null;
    } catch {
      return null;
    }
  };
  return {
    ...row,
    ntss6_items: parse(row.ntss6_items),
    dn4_items: parse(row.dn4_items),
    skin_temp_points: parse(row.skin_temp_points),
    abi_left_category: abiCategory(row.abi_left),
    abi_right_category: abiCategory(row.abi_right),
  };
}

module.exports = {
  round,
  computeAbi,
  abiCategory,
  computeNtss6,
  computeDn4,
  compliance,
  normalizeMeasurement,
  parseMeasurement,
  NTSS6_SYMPTOMS,
};
