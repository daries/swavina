const express = require("express");
const db = require("../db/database");
const auth = require("../middleware/auth");

const router = express.Router();

// GET semua jadwal
router.get("/", auth, (req, res) => {
  const schedules = db
    .prepare("SELECT * FROM schedules WHERE user_id = ? ORDER BY id DESC")
    .all(req.userId);
  res.json(schedules);
});

// POST buat jadwal baru
router.post("/", auth, (req, res) => {
  const { date, time, duration, temperature, vibration } = req.body;
  if (!date || !time || !duration) {
    return res.status(400).json({ message: "date, time, duration wajib diisi" });
  }

  const result = db
    .prepare(
      `INSERT INTO schedules (user_id, date, time, duration, temperature, vibration)
       VALUES (?, ?, ?, ?, ?, ?)`
    )
    .run(req.userId, date, time, duration, temperature || 38, vibration || 45);

  res.status(201).json({ id: result.lastInsertRowid });
});

// PUT update jadwal
router.put("/:id", auth, (req, res) => {
  const { date, time, duration, temperature, vibration } = req.body;

  const item = db
    .prepare("SELECT id FROM schedules WHERE id = ? AND user_id = ?")
    .get(req.params.id, req.userId);

  if (!item) return res.status(404).json({ message: "Jadwal tidak ditemukan" });

  db.prepare(
    `UPDATE schedules SET date=?, time=?, duration=?, temperature=?, vibration=? WHERE id=?`
  ).run(date, time, duration, temperature, vibration, req.params.id);

  res.json({ message: "Berhasil diupdate" });
});

// DELETE hapus jadwal
router.delete("/:id", auth, (req, res) => {
  const item = db
    .prepare("SELECT id FROM schedules WHERE id = ? AND user_id = ?")
    .get(req.params.id, req.userId);

  if (!item) return res.status(404).json({ message: "Jadwal tidak ditemukan" });

  db.prepare("DELETE FROM schedules WHERE id = ?").run(req.params.id);
  res.json({ message: "Berhasil dihapus" });
});

module.exports = router;
