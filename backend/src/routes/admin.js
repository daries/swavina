// API aplikasi monitoring (PWA) untuk perawat & peneliti.
const express = require("express");
const db = require("../db/database");
const auth = require("../middleware/auth");
const staff = require("../middleware/staff");
const alerts = require("../services/alerts");
const { compliance, normalizeMeasurement, parseMeasurement, round } = require("../services/clinical");
const { nextCode, isDisposableAuto, therapySessions } = require("../services/participants");

const THERAPY_RULE = "Pasien yang sudah melakukan terapi SWAVINA harus masuk kelompok intervensi";

const router = express.Router();
router.use(auth, staff);

const GROUPS = ["intervensi", "kontrol"];
// Responden penelitian = sudah disetujui (bukan "menunggu" / "ditolak").
const ENROLLED = "status NOT IN ('menunggu', 'ditolak')";
const PARTICIPANT_FIELDS = [
  "code", "name", "group_type", "phone", "sex", "birth_date", "dm_duration_years", "hba1c",
  "blood_glucose", "systolic", "diastolic", "height", "weight", "smoking", "physical_activity",
  "comorbidities", "antidiabetic", "analgesic", "neuropathy_drug", "notes", "study_start",
  "planned_sessions", "status",
];

const getParticipant = (id) => db.prepare("SELECT * FROM participants WHERE id = ?").get(id);

function withStats(p) {
  const openAlerts = db
    .prepare("SELECT COUNT(*) AS n FROM alerts WHERE participant_id = ? AND status != 'resolved'")
    .get(p.id).n;
  const tp = db
    .prepare("SELECT timepoint, MAX(measured_at) AS last FROM measurements WHERE participant_id = ? GROUP BY timepoint")
    .all(p.id);
  const has = (t) => tp.find((r) => r.timepoint === t)?.last || null;
  const user = p.user_id ? db.prepare("SELECT email FROM users WHERE id = ?").get(p.user_id) : null;
  // Post-test dijadwalkan 4 minggu setelah mulai penelitian.
  const postDue = p.study_start
    ? new Date(Date.parse(p.study_start) + 28 * 86400000).toISOString().slice(0, 10)
    : null;
  return {
    ...p,
    email: user?.email || null,
    compliance: compliance(db, p),
    open_alerts: openAlerts,
    pre_at: has("pre"),
    post_at: has("post"),
    post_due: postDue,
  };
}

function pickParticipant(body) {
  const out = {};
  for (const f of PARTICIPANT_FIELDS) if (body[f] !== undefined) out[f] = body[f] === "" ? null : body[f];
  return out;
}

/* ===== RINGKASAN DASHBOARD ===== */
router.get("/summary", (req, res) => {
  alerts.checkCompliance();
  const participants = db.prepare(`SELECT * FROM participants WHERE ${ENROLLED}`).all().map(withStats);
  const byGroup = (g) => participants.filter((p) => p.group_type === g);
  const active = (list) => list.filter((p) => p.status === "aktif");
  const interv = byGroup("intervensi");
  const withCompliance = interv.filter((p) => p.compliance.percent != null);
  const today = new Date().toISOString().slice(0, 10);
  const in7 = new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 10);

  res.json({
    groups: GROUPS.map((g) => ({
      group: g,
      total: byGroup(g).length,
      active: active(byGroup(g)).length,
      pre_done: byGroup(g).filter((p) => p.pre_at).length,
      post_done: byGroup(g).filter((p) => p.post_at).length,
    })),
    avg_compliance: withCompliance.length
      ? round(withCompliance.reduce((a, p) => a + p.compliance.percent, 0) / withCompliance.length, 1)
      : null,
    open_alerts: db.prepare("SELECT COUNT(*) AS n FROM alerts WHERE status != 'resolved'").get().n,
    critical_alerts: db
      .prepare("SELECT COUNT(*) AS n FROM alerts WHERE status != 'resolved' AND severity = 'critical'")
      .get().n,
    // Kunjungan pengukuran: belum pre-test, atau post-test jatuh tempo ≤ 7 hari / terlewat.
    visits: participants
      .filter((p) => p.status === "aktif")
      .map((p) => {
        if (!p.pre_at) return { ...p, visit: "pre", due: p.study_start || null };
        if (!p.post_at && p.post_due && p.post_due <= in7) return { ...p, visit: "post", due: p.post_due, overdue: p.post_due < today };
        return null;
      })
      .filter(Boolean)
      .sort((a, b) => String(a.due || "").localeCompare(String(b.due || ""))),
    recent_alerts: listAlerts({ status: "open", limit: 6 }),
    pending_approvals: db.prepare("SELECT COUNT(*) AS n FROM participants WHERE status = 'menunggu'").get().n,
  });
});

/* ===== PESERTA ===== */
router.get("/participants", (req, res) => {
  const { group, q, status } = req.query;
  let sql = "SELECT * FROM participants WHERE 1=1";
  const args = [];
  if (group) (sql += " AND group_type = ?"), args.push(group);
  if (status) (sql += " AND status = ?"), args.push(status);
  else sql += ` AND ${ENROLLED}`;
  if (q) (sql += " AND (name LIKE ? OR code LIKE ?)"), args.push(`%${q}%`, `%${q}%`);
  sql += " ORDER BY code";
  res.json(db.prepare(sql).all(...args).map(withStats));
});

router.post("/participants", (req, res) => {
  const data = pickParticipant(req.body);
  if (!data.name || !GROUPS.includes(data.group_type)) {
    return res.status(400).json({ message: "Nama dan kelompok wajib diisi" });
  }
  if (!data.code) data.code = nextCode(data.group_type);
  if (db.prepare("SELECT id FROM participants WHERE code = ?").get(data.code)) {
    return res.status(409).json({ message: `Kode responden ${data.code} sudah dipakai` });
  }
  const cols = Object.keys(data);
  const result = db
    .prepare(`INSERT INTO participants (${cols.join(",")}) VALUES (${cols.map(() => "?").join(",")})`)
    .run(...cols.map((c) => data[c]));
  res.status(201).json(withStats(getParticipant(result.lastInsertRowid)));
});

router.get("/participants/:id", (req, res) => {
  const p = getParticipant(req.params.id);
  if (!p) return res.status(404).json({ message: "Peserta tidak ditemukan" });
  res.json(withStats(p));
});

router.put("/participants/:id", (req, res) => {
  const p = getParticipant(req.params.id);
  if (!p) return res.status(404).json({ message: "Peserta tidak ditemukan" });
  const data = pickParticipant(req.body);
  if (data.group_type && !GROUPS.includes(data.group_type)) {
    return res.status(400).json({ message: "Kelompok tidak valid" });
  }
  if (data.group_type === "kontrol" && therapySessions(p.user_id)) {
    return res.status(400).json({ message: `${THERAPY_RULE} (${therapySessions(p.user_id)} sesi tercatat).` });
  }
  if (data.code && data.code !== p.code && db.prepare("SELECT id FROM participants WHERE code = ?").get(data.code)) {
    return res.status(409).json({ message: `Kode responden ${data.code} sudah dipakai` });
  }
  const cols = Object.keys(data);
  if (cols.length) {
    db.prepare(`UPDATE participants SET ${cols.map((c) => `${c} = ?`).join(", ")}, auto_created = 0 WHERE id = ?`).run(
      ...cols.map((c) => data[c]),
      p.id
    );
  }
  res.json(withStats(getParticipant(p.id)));
});

router.delete("/participants/:id", (req, res) => {
  const r = db.prepare("DELETE FROM participants WHERE id = ?").run(req.params.id);
  if (!r.changes) return res.status(404).json({ message: "Peserta tidak ditemukan" });
  res.json({ ok: true });
});

/* ===== PERSETUJUAN REGISTRASI ===== */
router.get("/approvals", (req, res) => {
  const status = req.query.status === "ditolak" ? "ditolak" : "menunggu";
  res.json(
    db
      .prepare(
        `SELECT p.*, u.email, u.created_at AS registered_at,
                (SELECT COUNT(*) FROM therapy_history t WHERE t.user_id = p.user_id) AS sessions
         FROM participants p LEFT JOIN users u ON u.id = p.user_id
         WHERE p.status = ? ORDER BY u.created_at DESC`
      )
      .all(status)
  );
});

/** Body: {group_type, study_start?, code?} → status aktif + kode resmi INT-/KON-. */
router.post("/participants/:id/approve", (req, res) => {
  const p = getParticipant(req.params.id);
  if (!p) return res.status(404).json({ message: "Peserta tidak ditemukan" });
  if (!["menunggu", "ditolak"].includes(p.status)) {
    return res.status(400).json({ message: "Responden ini sudah disetujui" });
  }
  const group = req.body.group_type;
  if (!GROUPS.includes(group)) return res.status(400).json({ message: "Pilih kelompok intervensi atau kontrol" });
  if (group === "kontrol" && therapySessions(p.user_id)) {
    return res.status(400).json({ message: `${THERAPY_RULE} (${therapySessions(p.user_id)} sesi tercatat).` });
  }
  const code = (req.body.code || "").trim() || nextCode(group);
  if (db.prepare("SELECT id FROM participants WHERE code = ? AND id != ?").get(code, p.id)) {
    return res.status(409).json({ message: `Kode responden ${code} sudah dipakai` });
  }
  db.prepare(
    `UPDATE participants SET status = 'aktif', group_type = ?, code = ?, study_start = COALESCE(?, study_start),
     auto_created = 0, approved_by = ?, approved_at = datetime('now') WHERE id = ?`
  ).run(group, code, req.body.study_start || null, req.userId, p.id);
  res.json(withStats(getParticipant(p.id)));
});

router.post("/participants/:id/reject", (req, res) => {
  const p = getParticipant(req.params.id);
  if (!p) return res.status(404).json({ message: "Peserta tidak ditemukan" });
  if (p.status !== "menunggu") return res.status(400).json({ message: "Hanya registrasi yang menunggu yang bisa ditolak" });
  db.prepare("UPDATE participants SET status = 'ditolak', approved_by = ?, approved_at = datetime('now') WHERE id = ?").run(
    req.userId,
    p.id
  );
  res.json({ ok: true });
});

/** Hubungkan peserta dengan akun aplikasi pasien (berdasarkan email). */
router.post("/participants/:id/link", (req, res) => {
  const p = getParticipant(req.params.id);
  if (!p) return res.status(404).json({ message: "Peserta tidak ditemukan" });
  const email = (req.body.email || "").trim();
  if (!email) {
    db.prepare("UPDATE participants SET user_id = NULL WHERE id = ?").run(p.id);
    return res.json(withStats(getParticipant(p.id)));
  }
  const user = db.prepare("SELECT id, role FROM users WHERE email = ?").get(email);
  if (!user) return res.status(404).json({ message: `Akun aplikasi ${email} tidak ditemukan` });
  if (user.role !== "patient") return res.status(400).json({ message: "Akun tersebut bukan akun pasien" });
  if (p.group_type === "kontrol" && therapySessions(user.id)) {
    return res.status(400).json({ message: `${THERAPY_RULE}. Akun ${email} sudah punya ${therapySessions(user.id)} sesi terapi.` });
  }
  const other = db.prepare("SELECT id, code FROM participants WHERE user_id = ? AND id != ?").get(user.id, p.id);
  if (other) {
    if (!isDisposableAuto(other.id)) {
      return res.status(409).json({ message: `Akun sudah terhubung ke responden ${other.code}` });
    }
    // Responden otomatis dari pendaftaran aplikasi digantikan oleh responden ini.
    db.prepare("DELETE FROM participants WHERE id = ?").run(other.id);
  }
  db.prepare("UPDATE participants SET user_id = ? WHERE id = ?").run(user.id, p.id);
  res.json(withStats(getParticipant(p.id)));
});

/** Akun pasien yang belum terhubung ke responden (untuk pilihan link). */
router.get("/app-users", (req, res) => {
  res.json(
    db
      .prepare(
        `SELECT u.id, u.email, pr.name, u.created_at FROM users u
         LEFT JOIN profiles pr ON pr.user_id = u.id
         WHERE u.role = 'patient'
         ORDER BY u.created_at DESC`
      )
      .all()
      .map((u) => {
        const linked = db.prepare("SELECT id, code FROM participants WHERE user_id = ?").get(u.id);
        if (!linked) return u;
        return isDisposableAuto(linked.id) ? { ...u, auto_code: linked.code } : null;
      })
      .filter(Boolean)
  );
});

/* ===== JADWAL TERAPI (ditulis ke tabel schedules milik akun pasien) ===== */
function linkedUser(req, res) {
  const p = getParticipant(req.params.id);
  if (!p) return res.status(404).json({ message: "Peserta tidak ditemukan" }), null;
  if (!p.user_id) return res.status(400).json({ message: "Peserta belum terhubung ke akun aplikasi" }), null;
  return p;
}

router.get("/participants/:id/schedules", (req, res) => {
  const p = linkedUser(req, res);
  if (!p) return;
  res.json(db.prepare("SELECT * FROM schedules WHERE user_id = ? ORDER BY date, time").all(p.user_id));
});

/** Body: {date, time, duration, temperature, vibration, repeat_days?} — repeat_days membuat jadwal harian berturut-turut. */
router.post("/participants/:id/schedules", (req, res) => {
  const p = linkedUser(req, res);
  if (!p) return;
  const { date, time, duration, temperature, vibration } = req.body;
  if (!date || !time || !duration) return res.status(400).json({ message: "Tanggal, jam, dan durasi wajib diisi" });
  const temp = Math.min(40, Math.max(30, Number(temperature) || 38));
  const vib = Math.min(60, Math.max(30, Number(vibration) || 45));
  const days = Math.min(60, Math.max(1, Number(req.body.repeat_days) || 1));
  const insert = db.prepare(
    "INSERT INTO schedules (user_id, date, time, duration, temperature, vibration) VALUES (?, ?, ?, ?, ?, ?)"
  );
  const start = Date.parse(date);
  db.transaction(() => {
    for (let i = 0; i < days; i++) {
      const d = new Date(start + i * 86400000).toISOString().slice(0, 10);
      insert.run(p.user_id, d, time.length === 5 ? `${time}:00` : time, Number(duration), temp, vib);
    }
  })();
  res.status(201).json({ created: days });
});

router.put("/participants/:id/schedules/:sid", (req, res) => {
  const p = linkedUser(req, res);
  if (!p) return;
  const { date, time, duration, temperature, vibration } = req.body;
  const r = db
    .prepare("UPDATE schedules SET date=?, time=?, duration=?, temperature=?, vibration=? WHERE id=? AND user_id=?")
    .run(date, time, duration, Math.min(40, temperature), vibration, req.params.sid, p.user_id);
  if (!r.changes) return res.status(404).json({ message: "Jadwal tidak ditemukan" });
  res.json({ ok: true });
});

router.delete("/participants/:id/schedules/:sid", (req, res) => {
  const p = linkedUser(req, res);
  if (!p) return;
  db.prepare("DELETE FROM schedules WHERE id = ? AND user_id = ?").run(req.params.sid, p.user_id);
  res.json({ ok: true });
});

/* ===== RIWAYAT TERAPI ===== */
router.get("/participants/:id/sessions", (req, res) => {
  const p = getParticipant(req.params.id);
  if (!p) return res.status(404).json({ message: "Peserta tidak ditemukan" });
  if (!p.user_id) return res.json([]);
  res.json(
    db.prepare("SELECT * FROM therapy_history WHERE user_id = ? ORDER BY date DESC, start_time DESC").all(p.user_id)
  );
});

/* ===== PENGUKURAN KLINIS ===== */
router.get("/participants/:id/measurements", (req, res) => {
  res.json(
    db
      .prepare("SELECT * FROM measurements WHERE participant_id = ? ORDER BY measured_at, id")
      .all(req.params.id)
      .map(parseMeasurement)
  );
});

router.post("/participants/:id/measurements", (req, res) => {
  const p = getParticipant(req.params.id);
  if (!p) return res.status(404).json({ message: "Peserta tidak ditemukan" });
  if (!["pre", "post", "lainnya"].includes(req.body.timepoint) || !req.body.measured_at) {
    return res.status(400).json({ message: "Waktu pengukuran (pre/post) dan tanggal wajib diisi" });
  }
  const m = normalizeMeasurement(req.body);
  const cols = Object.keys(m);
  const result = db
    .prepare(
      `INSERT INTO measurements (participant_id, created_by, ${cols.join(",")})
       VALUES (?, ?, ${cols.map(() => "?").join(",")})`
    )
    .run(p.id, req.userId, ...cols.map((c) => m[c]));
  alerts.onMeasurement(p.id, m, result.lastInsertRowid);
  res.status(201).json(parseMeasurement(db.prepare("SELECT * FROM measurements WHERE id = ?").get(result.lastInsertRowid)));
});

router.put("/measurements/:mid", (req, res) => {
  const old = db.prepare("SELECT * FROM measurements WHERE id = ?").get(req.params.mid);
  if (!old) return res.status(404).json({ message: "Pengukuran tidak ditemukan" });
  const m = normalizeMeasurement({ ...parseMeasurement(old), ...req.body });
  const cols = Object.keys(m);
  db.prepare(`UPDATE measurements SET ${cols.map((c) => `${c} = ?`).join(", ")} WHERE id = ?`).run(
    ...cols.map((c) => m[c]),
    old.id
  );
  alerts.onMeasurement(old.participant_id, m, old.id);
  res.json(parseMeasurement(db.prepare("SELECT * FROM measurements WHERE id = ?").get(old.id)));
});

router.delete("/measurements/:mid", (req, res) => {
  db.prepare("DELETE FROM measurements WHERE id = ?").run(req.params.mid);
  res.json({ ok: true });
});

/* ===== FORMULIR KEAMANAN ===== */
router.get("/participants/:id/adverse-events", (req, res) => {
  res.json(
    db
      .prepare("SELECT * FROM adverse_events WHERE participant_id = ? ORDER BY occurred_at DESC")
      .all(req.params.id)
      .map((e) => ({ ...e, types: e.types ? JSON.parse(e.types) : [] }))
  );
});

router.post("/participants/:id/adverse-events", (req, res) => {
  const p = getParticipant(req.params.id);
  if (!p) return res.status(404).json({ message: "Peserta tidak ditemukan" });
  const ev = {
    occurred_at: req.body.occurred_at,
    types: Array.isArray(req.body.types) ? req.body.types : [],
    severity: ["ringan", "sedang", "berat"].includes(req.body.severity) ? req.body.severity : "ringan",
    description: req.body.description || null,
    action_taken: req.body.action_taken || null,
    decision: req.body.decision === "hentikan" ? "hentikan" : "lanjut",
  };
  if (!ev.occurred_at) return res.status(400).json({ message: "Tanggal kejadian wajib diisi" });
  const r = db
    .prepare(
      `INSERT INTO adverse_events (participant_id, occurred_at, types, severity, description, action_taken, decision, created_by)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
    )
    .run(p.id, ev.occurred_at, JSON.stringify(ev.types), ev.severity, ev.description, ev.action_taken, ev.decision, req.userId);
  if (ev.decision === "hentikan") db.prepare("UPDATE participants SET status = 'drop_out' WHERE id = ?").run(p.id);
  alerts.onAdverseEvent(p.id, ev, r.lastInsertRowid);
  res.status(201).json({ id: r.lastInsertRowid });
});

router.delete("/adverse-events/:eid", (req, res) => {
  db.prepare("DELETE FROM adverse_events WHERE id = ?").run(req.params.eid);
  res.json({ ok: true });
});

/* ===== ALERT ===== */
function listAlerts({ status, participantId, limit } = {}) {
  let sql = `SELECT a.*, p.code, p.name, p.phone, p.group_type, u.name AS handled_by_name
             FROM alerts a JOIN participants p ON p.id = a.participant_id
             LEFT JOIN users u ON u.id = a.handled_by WHERE 1=1`;
  const args = [];
  if (status === "open") sql += " AND a.status != 'resolved'";
  else if (status) (sql += " AND a.status = ?"), args.push(status);
  if (participantId) (sql += " AND a.participant_id = ?"), args.push(participantId);
  sql += " ORDER BY CASE a.severity WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END, a.created_at DESC";
  if (limit) (sql += " LIMIT ?"), args.push(limit);
  return db.prepare(sql).all(...args);
}

router.get("/alerts", (req, res) => {
  alerts.checkCompliance();
  res.json(listAlerts({ status: req.query.status, participantId: req.query.participant_id }));
});

/** Body: {status: 'acknowledged'|'resolved', follow_up_note} */
router.patch("/alerts/:aid", (req, res) => {
  const { status, follow_up_note } = req.body;
  if (!["open", "acknowledged", "resolved"].includes(status)) {
    return res.status(400).json({ message: "Status alert tidak valid" });
  }
  const r = db
    .prepare(
      `UPDATE alerts SET status = ?, follow_up_note = COALESCE(?, follow_up_note),
       handled_by = ?, handled_at = datetime('now') WHERE id = ?`
    )
    .run(status, follow_up_note || null, req.userId, req.params.aid);
  if (!r.changes) return res.status(404).json({ message: "Alert tidak ditemukan" });
  res.json({ ok: true });
});

/* ===== ANALISIS: PRE–POST & INTERVENSI–KONTROL ===== */
const OUTCOMES = [
  { key: "abi_left", label: "ABI kiri" },
  { key: "abi_right", label: "ABI kanan" },
  { key: "ntss6_total", label: "NTSS-6" },
  { key: "nrs", label: "NRS" },
  { key: "dn4_total", label: "DN4" },
  { key: "skin_temp_left", label: "Suhu kulit kiri (°C)" },
  { key: "skin_temp_right", label: "Suhu kulit kanan (°C)" },
  { key: "lactate", label: "Laktat (mmol/L)" },
];

/** Pengukuran pre & post terakhir per peserta. */
function prePostRows() {
  const participants = db.prepare(`SELECT * FROM participants WHERE ${ENROLLED} ORDER BY group_type, code`).all();
  const latest = db.prepare(
    "SELECT * FROM measurements WHERE participant_id = ? AND timepoint = ? ORDER BY measured_at DESC, id DESC LIMIT 1"
  );
  return participants.map((p) => ({
    participant: p,
    pre: latest.get(p.id, "pre") || null,
    post: latest.get(p.id, "post") || null,
    compliance: compliance(db, p),
  }));
}

function describe(values) {
  const v = values.filter((x) => x != null && !Number.isNaN(x));
  if (!v.length) return { n: 0, mean: null, sd: null };
  const mean = v.reduce((a, b) => a + b, 0) / v.length;
  const sd = v.length > 1 ? Math.sqrt(v.reduce((a, b) => a + (b - mean) ** 2, 0) / (v.length - 1)) : null;
  return { n: v.length, mean: round(mean, 3), sd: sd == null ? null : round(sd, 3) };
}

router.get("/analysis", (req, res) => {
  const rows = prePostRows();
  const result = OUTCOMES.map((o) => {
    const groups = {};
    for (const g of GROUPS) {
      const gr = rows.filter((r) => r.participant.group_type === g);
      const pre = gr.map((r) => r.pre?.[o.key] ?? null);
      const post = gr.map((r) => r.post?.[o.key] ?? null);
      const delta = gr.map((r) => (r.pre?.[o.key] != null && r.post?.[o.key] != null ? r.post[o.key] - r.pre[o.key] : null));
      groups[g] = { pre: describe(pre), post: describe(post), delta: describe(delta) };
    }
    const di = groups.intervensi.delta.mean;
    const dk = groups.kontrol.delta.mean;
    return { ...o, groups, diff_in_delta: di != null && dk != null ? round(di - dk, 3) : null };
  });
  res.json({
    outcomes: result,
    n: Object.fromEntries(GROUPS.map((g) => [g, rows.filter((r) => r.participant.group_type === g).length])),
    complete_pairs: Object.fromEntries(
      GROUPS.map((g) => [g, rows.filter((r) => r.participant.group_type === g && r.pre && r.post).length])
    ),
  });
});

/* ===== EKSPOR CSV ===== */
function toCsv(rows) {
  if (!rows.length) return "";
  const headers = Object.keys(rows[0]);
  const esc = (v) => {
    if (v == null) return "";
    const s = String(v);
    return /[",;\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return "﻿" + [headers.join(","), ...rows.map((r) => headers.map((h) => esc(r[h])).join(","))].join("\n");
}

function sendCsv(res, name, rows) {
  const stamp = new Date().toISOString().slice(0, 10);
  res.setHeader("Content-Type", "text/csv; charset=utf-8");
  res.setHeader("Content-Disposition", `attachment; filename="swavina_${name}_${stamp}.csv"`);
  res.send(toCsv(rows));
}

/** Format lebar (1 baris per responden) siap untuk SPSS / SmartPLS. */
router.get("/export/dataset.csv", (req, res) => {
  const rows = prePostRows().map(({ participant: p, pre, post, compliance: c }) => {
    const row = {
      kode: p.code,
      kelompok: p.group_type === "intervensi" ? 1 : 0,
      status: p.status,
      jenis_kelamin: p.sex,
      tgl_lahir: p.birth_date,
      lama_dm_tahun: p.dm_duration_years,
      hba1c: p.hba1c,
      gula_darah: p.blood_glucose,
      sistolik: p.systolic,
      diastolik: p.diastolic,
      imt: p.height && p.weight ? round(p.weight / (p.height / 100) ** 2, 1) : null,
      merokok: p.smoking,
      aktivitas_fisik: p.physical_activity,
      penyakit_penyerta: p.comorbidities,
      terapi_antidiabetes: p.antidiabetic,
      analgesik: p.analgesic,
      obat_neuropati: p.neuropathy_drug,
      sesi_total: c.sessions,
      sesi_selesai: c.completed,
      sesi_direncanakan: c.planned,
      kepatuhan_persen: c.percent,
    };
    for (const o of OUTCOMES) {
      row[`${o.key}_pre`] = pre?.[o.key] ?? null;
      row[`${o.key}_post`] = post?.[o.key] ?? null;
      row[`${o.key}_delta`] = pre?.[o.key] != null && post?.[o.key] != null ? round(post[o.key] - pre[o.key], 3) : null;
    }
    row.tgl_pre = pre?.measured_at ?? null;
    row.tgl_post = post?.measured_at ?? null;
    return row;
  });
  sendCsv(res, "dataset", rows);
});

router.get("/export/measurements.csv", (req, res) => {
  const rows = db
    .prepare(
      `SELECT p.code AS kode, p.group_type AS kelompok, m.timepoint, m.measured_at,
              m.brachial_left, m.brachial_right, m.dp_left, m.pt_left, m.dp_right, m.pt_right,
              m.abi_left, m.abi_right, m.ntss6_total, m.dn4_total, m.nrs,
              m.skin_temp_left, m.skin_temp_right, m.room_temp, m.lactate, m.notes
       FROM measurements m JOIN participants p ON p.id = m.participant_id WHERE p.${ENROLLED} ORDER BY p.code, m.measured_at`
    )
    .all();
  sendCsv(res, "pengukuran", rows);
});

router.get("/export/sessions.csv", (req, res) => {
  const rows = db
    .prepare(
      `SELECT p.code AS kode, p.group_type AS kelompok, t.date AS tanggal, t.start_time AS jam_mulai,
              t.duration AS durasi_menit, t.target_duration AS target_menit, COALESCE(t.status, 'completed') AS status,
              t.stop_reason AS alasan_berhenti, t.temperature AS suhu_setting, t.vibration AS getar_setting,
              t.avg_temp AS suhu_aktual_rerata, t.max_temp AS suhu_aktual_maks, t.avg_vib AS getar_aktual_rerata,
              t.transport AS koneksi
       FROM therapy_history t JOIN participants p ON p.user_id = t.user_id WHERE p.${ENROLLED} ORDER BY p.code, t.date, t.start_time`
    )
    .all();
  sendCsv(res, "sesi_terapi", rows);
});

router.get("/export/adverse-events.csv", (req, res) => {
  const rows = db
    .prepare(
      `SELECT p.code AS kode, p.group_type AS kelompok, e.occurred_at AS tanggal, e.types AS jenis,
              e.severity AS keparahan, e.description AS deskripsi, e.action_taken AS tindakan, e.decision AS keputusan
       FROM adverse_events e JOIN participants p ON p.id = e.participant_id WHERE p.${ENROLLED} ORDER BY p.code, e.occurred_at`
    )
    .all();
  sendCsv(res, "keamanan", rows);
});

module.exports = router;
