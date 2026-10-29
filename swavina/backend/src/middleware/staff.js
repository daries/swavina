const db = require("../db/database");

const STAFF_ROLES = ["nurse", "researcher", "admin"];

/// Setelah middleware auth: hanya tenaga kesehatan / peneliti.
module.exports = function (req, res, next) {
  const user = db.prepare("SELECT id, role FROM users WHERE id = ?").get(req.userId);
  if (!user || !STAFF_ROLES.includes(user.role)) {
    return res.status(403).json({ message: "Akses khusus perawat/peneliti" });
  }
  req.userRole = user.role;
  next();
};

module.exports.STAFF_ROLES = STAFF_ROLES;
