// Alert Engine: membuat alert klinis untuk perawat/peneliti.
// Setiap alert punya dedupe_key agar kejadian yang sama tidak tercatat dua kali.

const db = require("../db/database");
const { compliance } = require("./clinical");

const SAFE_MAX_TEMP = 40; // °C, batas aman terapi (proposal Tahap II)
const SKIN_ASYMMETRY = 2.2; // °C, selisih suhu kulit kiri–kanan yang perlu diwaspadai
const INACTIVE_DAYS = 3; // hari tanpa terapi pada kelompok intervensi
const LOW_COMPLIANCE = 80; // % setelah minimal 7 hari penelitian

function raise(participantId, type, severity, message, dedupeKey) {
  db.prepare(
    `INSERT OR IGNORE INTO alerts (participant_id, type, severity, message, dedupe_key)
     VALUES (?, ?, ?, ?, ?)`
  ).run(participantId, type, severity, message, dedupeKey);
}

/** Setelah pengukuran klinis disimpan. */
function onMeasurement(participantId, m, measurementId) {
  const key = (t) => `${t}:m${measurementId}`;
  const lowAbi = [
    m.abi_left != null && m.abi_left <= 0.9 ? `kiri ${m.abi_left}` : null,
    m.abi_right != null && m.abi_right <= 0.9 ? `kanan ${m.abi_right}` : null,
  ].filter(Boolean);
  if (lowAbi.length) {
    raise(participantId, "abi_abnormal", "warning", `ABI abnormal (≤ 0,90): ${lowAbi.join(", ")}`, key("abi"));
  }
  if (m.skin_temp_left != null && m.skin_temp_right != null) {
    const diff = Math.abs(m.skin_temp_left - m.skin_temp_right);
    if (diff >= SKIN_ASYMMETRY) {
      raise(
        participantId,
        "suhu_asimetris",
        "warning",
        `Asimetri suhu kulit kaki ${diff.toFixed(1)}°C (kiri ${m.skin_temp_left}°C, kanan ${m.skin_temp_right}°C)`,
        key("asym")
      );
    }
  }
  if (m.nrs != null && m.timepoint !== "pre") {
    const pre = db
      .prepare("SELECT nrs FROM measurements WHERE participant_id = ? AND timepoint = 'pre' AND nrs IS NOT NULL ORDER BY measured_at DESC LIMIT 1")
      .get(participantId);
    if (pre && m.nrs - pre.nrs >= 2) {
      raise(participantId, "nyeri_meningkat", "warning", `Nyeri meningkat: NRS ${pre.nrs} → ${m.nrs}`, key("nrs"));
    }
  }
}

/** Setelah formulir keamanan disimpan. */
function onAdverseEvent(participantId, ev, eventId) {
  const types = ev.types || [];
  const critical = ev.severity === "berat" || types.includes("luka_bakar") || ev.decision === "hentikan";
  raise(
    participantId,
    "kejadian_tidak_diinginkan",
    critical ? "critical" : "warning",
    `Kejadian tidak diinginkan (${ev.severity}): ${types.join(", ").replace(/_/g, " ") || ev.description || "-"}`,
    `ae:${eventId}`
  );
}

/** Setelah sesi terapi dikirim aplikasi pasien. */
function onTherapySession(userId, session, sessionId) {
  const p = db.prepare("SELECT id FROM participants WHERE user_id = ?").get(userId);
  if (!p) return;
  if (session.max_temp != null && session.max_temp > SAFE_MAX_TEMP) {
    raise(
      p.id,
      "suhu_berlebih",
      "critical",
      `Suhu terapi mencapai ${session.max_temp}°C (batas aman ${SAFE_MAX_TEMP}°C)`,
      `temp:s${sessionId}`
    );
  }
}

/** Cek berkala kepatuhan kelompok intervensi. */
function checkCompliance() {
  const today = new Date().toISOString().slice(0, 10);
  const rows = db
    .prepare("SELECT * FROM participants WHERE group_type = 'intervensi' AND status = 'aktif' AND user_id IS NOT NULL AND study_start IS NOT NULL")
    .all();
  for (const p of rows) {
    const daysIn = Math.floor((Date.parse(today) - Date.parse(p.study_start)) / 86400000);
    if (daysIn < 0) continue;
    const c = compliance(db, p);
    const lastDate = c.last_session ? c.last_session.slice(0, 10) : p.study_start;
    const idle = Math.floor((Date.parse(today) - Date.parse(lastDate)) / 86400000);
    if (idle >= INACTIVE_DAYS) {
      raise(
        p.id,
        "tidak_terapi",
        "warning",
        `Tidak ada sesi terapi selama ${idle} hari (terakhir: ${c.last_session || "belum pernah"})`,
        `idle:${p.id}:${lastDate}`
      );
    }
    // Target sesi proporsional terhadap hari berjalan (maks. 28 hari / 4 minggu).
    if (daysIn >= 7) {
      const expected = Math.min(c.planned, Math.round((c.planned * Math.min(daysIn, 28)) / 28));
      const pct = expected ? (c.completed / expected) * 100 : 100;
      if (pct < LOW_COMPLIANCE) {
        const week = Math.floor(daysIn / 7);
        raise(
          p.id,
          "kepatuhan_rendah",
          "warning",
          `Kepatuhan rendah: ${c.completed} dari ${expected} sesi yang diharapkan (${pct.toFixed(0)}%) pada minggu ke-${week}`,
          `compliance:${p.id}:w${week}`
        );
      }
    }
  }
}

function start() {
  checkCompliance();
  setInterval(checkCompliance, 60 * 60 * 1000);
}

module.exports = { onMeasurement, onAdverseEvent, onTherapySession, checkCompliance, start, SAFE_MAX_TEMP };
