// Ganti password akun (pasien maupun tenaga kesehatan) tanpa mengubah data lain.
// Pemakaian: npm run reset-password -- <email> <password-baru>
require("dotenv").config();
const bcrypt = require("bcryptjs");
const db = require("../src/db/database");

const [email, password] = process.argv.slice(2);
if (!email || !password) {
  console.error("Pemakaian: npm run reset-password -- <email> <password-baru>");
  process.exit(1);
}

const hashed = bcrypt.hashSync(password, 10);
const result = db.prepare("UPDATE users SET password = ? WHERE email = ?").run(hashed, email);
if (result.changes === 0) {
  console.error(`Akun ${email} tidak ditemukan.`);
  process.exit(1);
}
console.log(`Password ${email} diperbarui.`);
