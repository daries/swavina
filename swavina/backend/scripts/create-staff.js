// Buat / perbarui akun tenaga kesehatan untuk aplikasi monitoring.
// Pemakaian: npm run create-staff -- <email> <password> "<nama>" [nurse|researcher|admin]
require("dotenv").config();
const bcrypt = require("bcryptjs");
const db = require("../src/db/database");
const { STAFF_ROLES } = require("../src/middleware/staff");

const [email, password, name, role = "researcher"] = process.argv.slice(2);
if (!email || !password || !name || !STAFF_ROLES.includes(role)) {
  console.error('Pemakaian: npm run create-staff -- <email> <password> "<nama>" [nurse|researcher|admin]');
  process.exit(1);
}

const hashed = bcrypt.hashSync(password, 10);
const existing = db.prepare("SELECT id FROM users WHERE email = ?").get(email);
if (existing) {
  db.prepare("UPDATE users SET password = ?, name = ?, role = ? WHERE id = ?").run(hashed, name, role, existing.id);
  console.log(`Akun ${email} diperbarui (peran: ${role}).`);
} else {
  db.prepare("INSERT INTO users (email, password, name, role) VALUES (?, ?, ?, ?)").run(email, hashed, name, role);
  console.log(`Akun ${email} dibuat (peran: ${role}).`);
}
