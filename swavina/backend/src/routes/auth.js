const express = require("express");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const db = require("../db/database");
const authMiddleware = require("../middleware/auth");
const { ensureParticipantForUser } = require("../services/participants");

const router = express.Router();

// Register
router.post("/register", (req, res) => {
  const { email, password, name } = req.body;
  if (!email || !password) {
    return res.status(400).json({ message: "Email dan password wajib diisi" });
  }

  const existing = db.prepare("SELECT id FROM users WHERE email = ?").get(email);
  if (existing) {
    return res.status(409).json({ message: "Email sudah terdaftar" });
  }

  const hashed = bcrypt.hashSync(password, 10);
  const result = db.prepare("INSERT INTO users (email, password) VALUES (?, ?)").run(email, hashed);

  db.prepare("INSERT INTO profiles (user_id, name) VALUES (?, ?)").run(result.lastInsertRowid, name || "");
  ensureParticipantForUser(result.lastInsertRowid);

  const token = jwt.sign({ id: result.lastInsertRowid }, process.env.JWT_SECRET, { expiresIn: "30d" });
  res.status(201).json({ token, userId: result.lastInsertRowid });
});

// Login
router.post("/login", (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) {
    return res.status(400).json({ message: "Email dan password wajib diisi" });
  }

  const user = db.prepare("SELECT * FROM users WHERE email = ?").get(email);
  if (!user) {
    return res.status(401).json({ message: "Email atau password salah" });
  }

  const valid = bcrypt.compareSync(password, user.password);
  if (!valid) {
    return res.status(401).json({ message: "Email atau password salah" });
  }

  const token = jwt.sign({ id: user.id }, process.env.JWT_SECRET, { expiresIn: "30d" });
  res.json({ token, userId: user.id, role: user.role, name: user.name });
});

// Get current user
router.get("/me", authMiddleware, (req, res) => {
  const user = db.prepare("SELECT id, email, role, name, created_at FROM users WHERE id = ?").get(req.userId);
  if (!user) return res.status(404).json({ message: "User tidak ditemukan" });
  res.json(user);
});

module.exports = router;
