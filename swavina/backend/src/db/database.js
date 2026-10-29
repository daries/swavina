const Database = require("better-sqlite3");
const path = require("path");

const db = new Database(process.env.DB_PATH || path.join(__dirname, "../../swavina.db"));

db.pragma("journal_mode = WAL");
db.pragma("foreign_keys = ON");

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS profiles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER UNIQUE NOT NULL,
    name TEXT,
    birth_date TEXT,
    height REAL,
    height_date TEXT,
    weight REAL,
    weight_date TEXT,
    blood_sugar TEXT,
    blood_sugar_date TEXT,
    blood_pressure TEXT,
    blood_pressure_date TEXT,
    profile_image TEXT,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS therapy_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    date TEXT,
    start_time TEXT,
    duration INTEGER,
    temperature INTEGER,
    vibration INTEGER,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS schedules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    date TEXT,
    time TEXT,
    duration INTEGER,
    temperature INTEGER,
    vibration INTEGER,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  );
`);

/* ===== MIGRASI: penelitian & monitoring (aplikasi admin) ===== */

// Tambah kolom bila belum ada (SQLite tidak punya ADD COLUMN IF NOT EXISTS).
function addColumn(table, column, definition) {
  const exists = db.prepare(`PRAGMA table_info(${table})`).all().some((c) => c.name === column);
  if (!exists) db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
}

// Peran akun: patient (aplikasi pasien), nurse, researcher, admin (aplikasi monitoring)
addColumn("users", "role", "TEXT NOT NULL DEFAULT 'patient'");
addColumn("users", "name", "TEXT");

// Log sesi terapi untuk kepatuhan & keamanan
addColumn("therapy_history", "status", "TEXT DEFAULT 'completed'"); // completed | stopped
addColumn("therapy_history", "target_duration", "INTEGER");
addColumn("therapy_history", "stop_reason", "TEXT");
addColumn("therapy_history", "max_temp", "REAL"); // suhu aktual tertinggi (°C)
addColumn("therapy_history", "avg_temp", "REAL");
addColumn("therapy_history", "avg_vib", "REAL");
addColumn("therapy_history", "transport", "TEXT"); // bluetooth | wifi

db.exec(`
  -- Responden penelitian (kelompok intervensi / kontrol). Kelompok kontrol
  -- tidak wajib punya akun aplikasi, sehingga user_id boleh kosong.
  CREATE TABLE IF NOT EXISTS participants (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    group_type TEXT NOT NULL CHECK (group_type IN ('intervensi', 'kontrol')),
    user_id INTEGER UNIQUE,
    phone TEXT,
    sex TEXT,
    birth_date TEXT,
    dm_duration_years REAL,
    hba1c REAL,
    blood_glucose REAL,
    systolic INTEGER,
    diastolic INTEGER,
    height REAL,
    weight REAL,
    smoking TEXT,
    physical_activity TEXT,
    comorbidities TEXT,
    antidiabetic TEXT,
    analgesic TEXT,
    neuropathy_drug TEXT,
    notes TEXT,
    study_start TEXT,
    planned_sessions INTEGER NOT NULL DEFAULT 28,
    status TEXT NOT NULL DEFAULT 'aktif',
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
  );

  -- Kunjungan pengukuran klinis (pre-test / post-test)
  CREATE TABLE IF NOT EXISTS measurements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    participant_id INTEGER NOT NULL,
    timepoint TEXT NOT NULL CHECK (timepoint IN ('pre', 'post', 'lainnya')),
    measured_at TEXT NOT NULL,
    brachial_left REAL, brachial_right REAL,
    dp_left REAL, pt_left REAL, dp_right REAL, pt_right REAL,
    abi_left REAL, abi_right REAL,
    ntss6_items TEXT, ntss6_total REAL,
    dn4_items TEXT, dn4_total INTEGER,
    nrs INTEGER,
    skin_temp_left REAL, skin_temp_right REAL, skin_temp_points TEXT,
    room_temp REAL,
    lactate REAL,
    notes TEXT,
    created_by INTEGER,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (participant_id) REFERENCES participants(id) ON DELETE CASCADE
  );

  -- Formulir keamanan / kejadian tidak diinginkan
  CREATE TABLE IF NOT EXISTS adverse_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    participant_id INTEGER NOT NULL,
    occurred_at TEXT NOT NULL,
    types TEXT,
    severity TEXT NOT NULL DEFAULT 'ringan',
    description TEXT,
    action_taken TEXT,
    decision TEXT NOT NULL DEFAULT 'lanjut',
    created_by INTEGER,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (participant_id) REFERENCES participants(id) ON DELETE CASCADE
  );

  -- Alert klinis untuk perawat/peneliti
  CREATE TABLE IF NOT EXISTS alerts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    participant_id INTEGER NOT NULL,
    type TEXT NOT NULL,
    severity TEXT NOT NULL DEFAULT 'warning',
    message TEXT NOT NULL,
    dedupe_key TEXT UNIQUE,
    status TEXT NOT NULL DEFAULT 'open',
    follow_up_note TEXT,
    handled_by INTEGER,
    handled_at TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (participant_id) REFERENCES participants(id) ON DELETE CASCADE
  );
`);

// Responden yang dibuat otomatis dari pendaftaran aplikasi pasien
addColumn("participants", "auto_created", "INTEGER NOT NULL DEFAULT 0");
// Persetujuan responden hasil registrasi aplikasi (status: menunggu → aktif / ditolak)
addColumn("participants", "approved_by", "INTEGER");
addColumn("participants", "approved_at", "TEXT");
// Responden otomatis yang belum pernah disetujui peneliti → antrean persetujuan.
db.exec(`UPDATE participants SET status = 'menunggu', code = 'REG-' || user_id
         WHERE auto_created = 1 AND approved_at IS NULL AND user_id IS NOT NULL
           AND (status = 'aktif' OR (status = 'menunggu' AND code NOT LIKE 'REG-%'))`);

module.exports = db;
