// Responden otomatis untuk akun pasien yang mendaftar lewat aplikasi.
const db = require("../db/database");

/** Kode responden berikutnya untuk kelompok, mis. INT-003 / KON-012. */
function nextCode(group) {
  const prefix = group === "kontrol" ? "KON" : "INT";
  const rows = db.prepare("SELECT code FROM participants WHERE code LIKE ?").all(`${prefix}-%`);
  const max = rows.reduce((m, r) => Math.max(m, Number(r.code.slice(prefix.length + 1)) || 0), 0);
  return `${prefix}-${String(max + 1).padStart(3, "0")}`;
}

/**
 * Pastikan akun pasien punya data responden. Hasil registrasi berstatus
 * "menunggu" dengan kode sementara REG-<id> sampai disetujui peneliti/perawat
 * (kelompok & kode resmi ditetapkan saat persetujuan). Aplikasi tetap bisa dipakai.
 * Mengembalikan id responden, atau null jika akun bukan pasien.
 */
function ensureParticipantForUser(userId) {
  const user = db
    .prepare(
      `SELECT u.id, u.email, u.role, u.created_at, pr.name FROM users u
       LEFT JOIN profiles pr ON pr.user_id = u.id WHERE u.id = ?`
    )
    .get(userId);
  if (!user || user.role !== "patient") return null;
  const existing = db.prepare("SELECT id FROM participants WHERE user_id = ?").get(userId);
  if (existing) return existing.id;

  const name = (user.name || "").trim() || user.email.split("@")[0];
  const result = db
    .prepare(
      `INSERT INTO participants (code, name, group_type, user_id, status, auto_created, notes)
       VALUES (?, ?, 'intervensi', ?, 'menunggu', 1, ?)`
    )
    .run(`REG-${userId}`, name, userId, `Registrasi aplikasi (${user.email}).`);
  return result.lastInsertRowid;
}

/** Migrasi: semua akun pasien yang belum punya data responden. */
function backfillParticipants() {
  const users = db
    .prepare(
      `SELECT id FROM users WHERE role = 'patient'
       AND id NOT IN (SELECT user_id FROM participants WHERE user_id IS NOT NULL) ORDER BY id`
    )
    .all();
  const created = db.transaction(() => users.map((u) => ensureParticipantForUser(u.id)))();
  if (created.length) console.log(`Migrasi responden: ${created.length} akun pasien ditambahkan sebagai responden.`);
  // Responden kontrol yang ternyata sudah melakukan terapi → intervensi.
  const kontrolWithTherapy = db
    .prepare(
      `SELECT DISTINCT p.user_id FROM participants p JOIN therapy_history t ON t.user_id = p.user_id
       WHERE p.group_type = 'kontrol'`
    )
    .all();
  for (const r of kontrolWithTherapy) enforceTherapyGroup(r.user_id);
  return created.length;
}

/**
 * Responden otomatis yang masih "kosong" (belum ada pengukuran, kejadian, atau
 * data yang diubah peneliti) boleh dilebur saat akunnya dihubungkan ke responden lain.
 */
function isDisposableAuto(participantId) {
  const p = db.prepare("SELECT auto_created FROM participants WHERE id = ?").get(participantId);
  if (!p || !p.auto_created) return false;
  const used =
    db.prepare("SELECT COUNT(*) AS n FROM measurements WHERE participant_id = ?").get(participantId).n +
    db.prepare("SELECT COUNT(*) AS n FROM adverse_events WHERE participant_id = ?").get(participantId).n;
  return used === 0;
}

/** Jumlah sesi terapi milik akun yang terhubung ke responden. */
function therapySessions(userId) {
  if (!userId) return 0;
  return db.prepare("SELECT COUNT(*) AS n FROM therapy_history WHERE user_id = ?").get(userId).n;
}

/**
 * Aturan penelitian: semua pasien yang melakukan terapi SWAVINA masuk kelompok
 * intervensi. Responden kontrol yang tercatat melakukan terapi dipindahkan ke
 * intervensi (kode KON- diganti INT-) dan peneliti diberi alert.
 * Mengembalikan responden setelah perubahan, atau null jika tidak ada perubahan.
 */
function enforceTherapyGroup(userId) {
  const p = db.prepare("SELECT * FROM participants WHERE user_id = ?").get(userId);
  if (!p || p.group_type !== "kontrol" || !therapySessions(userId)) return null;
  const code = p.code.startsWith("KON-") ? nextCode("intervensi") : p.code;
  db.prepare("UPDATE participants SET group_type = 'intervensi', code = ? WHERE id = ?").run(code, p.id);
  if (!["menunggu", "ditolak"].includes(p.status)) {
    db.prepare(
      `INSERT OR IGNORE INTO alerts (participant_id, type, severity, message, dedupe_key)
       VALUES (?, 'pindah_kelompok', 'warning', ?, ?)`
    ).run(
      p.id,
      `Responden kontrol ${p.code} melakukan terapi SWAVINA dan dipindahkan ke kelompok intervensi sebagai ${code}. Periksa kontaminasi kelompok kontrol.`,
      `group:${p.id}`
    );
  }
  return db.prepare("SELECT * FROM participants WHERE id = ?").get(p.id);
}

module.exports = {
  nextCode,
  ensureParticipantForUser,
  backfillParticipants,
  isDisposableAuto,
  therapySessions,
  enforceTherapyGroup,
};
