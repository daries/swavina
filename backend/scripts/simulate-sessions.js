// Buat sesi terapi simulasi seolah-olah dikirim aplikasi dari perangkat SWAVINA.
// Pembacaan sensor suhu & getar dibangkitkan per detik lalu diringkas
// (max_temp, avg_temp, avg_vib) seperti di lib/screens/therapy_screen.dart.
// Sesi simulasi ditandai transport = 'simulasi' agar mudah dibedakan & dihapus.
//
// Pemakaian:
//   npm run simulate-sessions -- <email> [jumlah-hari]   (default: sejak study_start, maks. 28 hari)
//   npm run simulate-sessions -- <email> --hapus         (hapus semua sesi simulasi akun tsb.)
require("dotenv").config();
const db = require("../src/db/database");
const alerts = require("../src/services/alerts");
const { enforceTherapyGroup } = require("../src/services/participants");

const TRANSPORT = "simulasi";
const [email, arg] = process.argv.slice(2);
if (!email) {
  console.error("Pemakaian: npm run simulate-sessions -- <email> [jumlah-hari | --hapus]");
  process.exit(1);
}

const user = db.prepare("SELECT id FROM users WHERE email = ?").get(email);
if (!user) {
  console.error(`Akun ${email} tidak ditemukan.`);
  process.exit(1);
}

if (arg === "--hapus") {
  const ids = db
    .prepare("SELECT id FROM therapy_history WHERE user_id = ? AND transport = ?")
    .all(user.id, TRANSPORT)
    .map((s) => s.id);
  const delAlert = db.prepare("DELETE FROM alerts WHERE dedupe_key = ?");
  const delSession = db.prepare("DELETE FROM therapy_history WHERE id = ?");
  db.transaction(() => ids.forEach((id) => (delAlert.run(`temp:s${id}`), delSession.run(id))))();
  console.log(`${ids.length} sesi simulasi ${email} (beserta alert suhunya) dihapus.`);
  process.exit(0);
}

const DAY = 86400000;
const today = new Date(new Date().toISOString().slice(0, 10));
const participant = db.prepare("SELECT study_start FROM participants WHERE user_id = ?").get(user.id);
let days = Number(arg);
if (!days) {
  const start = participant?.study_start ? Date.parse(participant.study_start) : today - 14 * DAY;
  days = Math.min(28, Math.max(1, Math.round((today - start) / DAY)));
}

const rand = (min, max) => min + Math.random() * (max - min);
const pick = (items) => items[Math.floor(Math.random() * items.length)];
const round1 = (v) => Math.round(v * 10) / 10;
const pad = (n) => String(n).padStart(2, "0");

/** Bangkitkan pembacaan sensor per detik selama `minutes` lalu ringkas. */
function readSensors(setTemp, setVib, minutes, overheat) {
  let temp = rand(30.5, 32.5); // suhu awal elemen ≈ suhu kulit kaki
  let maxTemp = 0, tempSum = 0, vibSum = 0;
  const seconds = minutes * 60;
  // Kontrol suhu menahan sedikit di bawah setelan; sesekali meleset (overheat).
  const peak = overheat ? setTemp + rand(1.0, 1.8) : setTemp - rand(0.2, 0.5);
  for (let s = 0; s < seconds; s++) {
    temp += (peak - temp) * 0.006; // pemanasan eksponensial
    const reading = temp + rand(-0.1, 0.1); // derau sensor
    const vib = setVib + rand(-1.5, 1.5);
    maxTemp = Math.max(maxTemp, reading);
    tempSum += reading;
    vibSum += vib;
  }
  return { max_temp: round1(maxTemp), avg_temp: round1(tempSum / seconds), avg_vib: round1(vibSum / seconds) };
}

const insert = db.prepare(
  `INSERT INTO therapy_history (user_id, date, start_time, duration, temperature, vibration,
     status, target_duration, stop_reason, max_temp, avg_temp, avg_vib, transport)
   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
);

let created = 0, stopped = 0, overheated = 0;
for (let d = days; d >= 1; d--) {
  if (Math.random() < 0.12) continue; // sesekali pasien tidak terapi
  const date = new Date(today - d * DAY).toISOString().slice(0, 10);
  const time = `${pad(pick([6, 7, 8, 16, 17, 19, 20]))}:${pad(Math.floor(rand(0, 60)))}:${pad(Math.floor(rand(0, 60)))}`;
  const setTemp = pick([37, 38, 38, 39, 40]);
  const setVib = pick([40, 45, 45, 50]);
  const target = 20;
  const isStopped = Math.random() < 0.08;
  const duration = isStopped ? Math.floor(rand(4, target)) : target;
  const overheat = Math.random() < 0.04;
  const reading = readSensors(setTemp, setVib, duration, overheat);

  const r = insert.run(
    user.id, date, time, duration, setTemp, setVib,
    isStopped ? "stopped" : "completed", target, isStopped ? "Dihentikan pasien" : null,
    reading.max_temp, reading.avg_temp, reading.avg_vib, TRANSPORT
  );
  alerts.onTherapySession(user.id, { max_temp: reading.max_temp }, r.lastInsertRowid);
  created++;
  if (isStopped) stopped++;
  if (reading.max_temp > alerts.SAFE_MAX_TEMP) overheated++;
}
enforceTherapyGroup(user.id);

console.log(
  `${created} sesi simulasi dibuat untuk ${email} (${days} hari terakhir): ` +
    `${stopped} dihentikan, ${overheated} melebihi ${alerts.SAFE_MAX_TEMP}°C.`
);
