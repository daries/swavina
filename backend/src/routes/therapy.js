const express = require("express");
const db = require("../db/database");
const auth = require("../middleware/auth");
const alerts = require("../services/alerts");
const { enforceTherapyGroup } = require("../services/participants");

const router = express.Router();

// GET semua history terapi
router.get("/", auth, (req, res) => {
  const history = db
    .prepare("SELECT * FROM therapy_history WHERE user_id = ? ORDER BY id DESC")
    .all(req.userId);
  res.json(history);
});

// POST simpan sesi terapi
router.post("/", auth, (req, res) => {
  const { date, start_time, duration, temperature, vibration } = req.body;
  const { status, target_duration, stop_reason, max_temp, avg_temp, avg_vib, transport } = req.body;
  if (!duration || !temperature || !vibration) {
    return res.status(400).json({ message: "duration, temperature, vibration wajib diisi" });
  }

  const result = db
    .prepare(
      `INSERT INTO therapy_history (user_id, date, start_time, duration, temperature, vibration,
         status, target_duration, stop_reason, max_temp, avg_temp, avg_vib, transport)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    )
    .run(
      req.userId, date, start_time, duration, temperature, vibration,
      status === "stopped" ? "stopped" : "completed", target_duration ?? null, stop_reason ?? null,
      max_temp ?? null, avg_temp ?? null, avg_vib ?? null, transport ?? null
    );

  enforceTherapyGroup(req.userId);
  alerts.onTherapySession(req.userId, { max_temp }, result.lastInsertRowid);

  res.status(201).json({ id: result.lastInsertRowid });
});

// DELETE hapus sesi terapi
router.delete("/:id", auth, (req, res) => {
  const item = db
    .prepare("SELECT id FROM therapy_history WHERE id = ? AND user_id = ?")
    .get(req.params.id, req.userId);

  if (!item) return res.status(404).json({ message: "Data tidak ditemukan" });

  db.prepare("DELETE FROM therapy_history WHERE id = ?").run(req.params.id);
  res.json({ message: "Berhasil dihapus" });
});

module.exports = router;
