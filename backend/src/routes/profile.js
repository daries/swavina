const express = require("express");
const db = require("../db/database");
const auth = require("../middleware/auth");

const router = express.Router();

// GET profile
router.get("/", auth, (req, res) => {
  const profile = db
    .prepare("SELECT * FROM profiles WHERE user_id = ?")
    .get(req.userId);

  if (!profile) return res.status(404).json({ message: "Profile tidak ditemukan" });
  res.json(profile);
});

// PUT update profile
router.put("/", auth, (req, res) => {
  const {
    name,
    birth_date,
    height,
    height_date,
    weight,
    weight_date,
    blood_sugar,
    blood_sugar_date,
    blood_pressure,
    blood_pressure_date,
    profile_image,
  } = req.body;

  db.prepare(`
    UPDATE profiles SET
      name = ?,
      birth_date = ?,
      height = ?,
      height_date = ?,
      weight = ?,
      weight_date = ?,
      blood_sugar = ?,
      blood_sugar_date = ?,
      blood_pressure = ?,
      blood_pressure_date = ?,
      profile_image = ?
    WHERE user_id = ?
  `).run(
    name,
    birth_date,
    height,
    height_date,
    weight,
    weight_date,
    blood_sugar,
    blood_sugar_date,
    blood_pressure,
    blood_pressure_date,
    profile_image,
    req.userId
  );

  res.json({ message: "Profile berhasil diupdate" });
});

module.exports = router;
