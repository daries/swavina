const express = require("express");
const db = require("../db/database");
const auth = require("../middleware/auth");

const router = express.Router();

router.get("/", auth, (req, res) => {
  // Format tanggal sama dengan yang dikirim app Flutter: yyyy-MM-dd (waktu lokal server)
  const now = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  const today = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;

  // Progress harian
  const todaySessions = db
    .prepare(
      "SELECT SUM(duration) as total FROM therapy_history WHERE user_id = ? AND date = ?"
    )
    .get(req.userId, today);

  // Sesi terakhir
  const lastSession = db
    .prepare(
      "SELECT * FROM therapy_history WHERE user_id = ? ORDER BY id DESC LIMIT 1"
    )
    .get(req.userId);

  // Ringkasan mingguan (7 hari terakhir)
  const weekly = db
    .prepare(
      `SELECT COUNT(*) as sessions, SUM(duration) as total_duration
       FROM therapy_history
       WHERE user_id = ? AND created_at >= datetime('now', '-7 days')`
    )
    .get(req.userId);

  res.json({
    today_duration: todaySessions?.total || 0,
    daily_target: 30,
    last_session: lastSession || null,
    weekly_sessions: weekly?.sessions || 0,
    weekly_duration: weekly?.total_duration || 0,
  });
});

module.exports = router;
