const jwt = require("jsonwebtoken");

module.exports = function (req, res, next) {
  const header = req.headers.authorization;
  if (!header) return res.status(401).json({ message: "Token tidak ada" });

  const token = header.split(" ")[1];
  if (!token) return res.status(401).json({ message: "Token tidak valid" });

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.userId = decoded.id;
    next();
  } catch {
    res.status(401).json({ message: "Token expired atau tidak valid" });
  }
};
