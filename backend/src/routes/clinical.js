// Data klinis read-only untuk aplikasi pasien (hasil input perawat/peneliti).
const express = require("express");
const db = require("../db/database");
const auth = require("../middleware/auth");
const { parseMeasurement } = require("../services/clinical");

const router = express.Router();

router.get("/", auth, (req, res) => {
  // Catatan internal (notes) dan no. HP tidak dikirim ke aplikasi pasien.
  const p = db
    .prepare(
      `SELECT id, code, group_type, study_start, planned_sessions, status,
              sex, birth_date, dm_duration_years, hba1c, blood_glucose, systolic, diastolic,
              height, weight, smoking, physical_activity, comorbidities, antidiabetic,
              analgesic, neuropathy_drug
       FROM participants WHERE user_id = ?`
    )
    .get(req.userId);
  if (!p) return res.json({ participant: null, measurements: [], adverse_events: [] });
  const measurements = db
    .prepare(
      `SELECT id, timepoint, measured_at, abi_left, abi_right, ntss6_total, dn4_total, nrs,
              skin_temp_left, skin_temp_right, lactate
       FROM measurements WHERE participant_id = ? ORDER BY measured_at`
    )
    .all(p.id)
    .map(parseMeasurement);
  const adverseEvents = db
    .prepare(
      `SELECT id, occurred_at, types, severity, description, action_taken, decision
       FROM adverse_events WHERE participant_id = ? ORDER BY occurred_at DESC`
    )
    .all(p.id)
    .map((e) => ({ ...e, types: e.types ? JSON.parse(e.types) : [] }));
  res.json({ participant: p, measurements, adverse_events: adverseEvents });
});

module.exports = router;
