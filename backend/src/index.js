require("dotenv").config();
const express = require("express");
const path = require("path");
const fs = require("fs");
const cors = require("cors");
const swaggerUi = require("swagger-ui-express");
const swaggerSpec = require("./swagger");

const authRoutes = require("./routes/auth");
const therapyRoutes = require("./routes/therapy");
const scheduleRoutes = require("./routes/schedule");
const profileRoutes = require("./routes/profile");
const dashboardRoutes = require("./routes/dashboard");
const adminRoutes = require("./routes/admin");
const clinicalRoutes = require("./routes/clinical");
const alertEngine = require("./services/alerts");
const { backfillParticipants } = require("./services/participants");

const app = express();
const PORT = process.env.PORT || 3000;
const PUBLIC_URL = process.env.PUBLIC_URL || `http://localhost:${PORT}`;

app.use(cors({ exposedHeaders: ["Content-Disposition"] })); // nama file ekspor CSV terbaca lintas domain
app.use(express.json({ limit: "10mb" }));

app.use("/api/auth", authRoutes);
app.use("/api/therapy", therapyRoutes);
app.use("/api/schedule", scheduleRoutes);
app.use("/api/profile", profileRoutes);
app.use("/api/dashboard", dashboardRoutes);
app.use("/api/admin", adminRoutes);
app.use("/api/clinical", clinicalRoutes);


app.use("/docs", swaggerUi.serve, swaggerUi.setup(swaggerSpec, {
  customSiteTitle: "Swavina API Docs",
  customCss: ".swagger-ui .topbar { background-color: #c35423; }",
}));

app.get("/docs.json", (req, res) => {
  res.json(swaggerSpec);
});

app.get("/api", (req, res) => {
  res.json({ app: "Swavina API", version: "1.0.0", status: "running", docs: `${PUBLIC_URL}/docs` });
});

// Aplikasi monitoring perawat/peneliti (PWA hasil build admin/ → admin/dist) di root "/".
const adminDist = path.join(__dirname, "../../admin/dist");
if (fs.existsSync(adminDist)) {
  // Alamat lama /admin/... dialihkan ke root.
  app.get(/^\/admin(\/.*)?$/, (req, res) => res.redirect(302, req.params[0] || "/"));
  app.use(express.static(adminDist));
  // Fallback SPA: semua GET selain /api & /docs → index.html (React Router).
  app.get(/^(?!\/(api|docs)(\/|$)).*/, (req, res) => res.sendFile(path.join(adminDist, "index.html")));
} else {
  app.get("/", (req, res) => res.redirect("/api"));
}

app.use((req, res) => {
  res.status(404).json({ message: "Endpoint tidak ditemukan" });
});

app.listen(PORT, () => {
  backfillParticipants();
  alertEngine.start();
  console.log(`Swavina Backend berjalan di http://localhost:${PORT} (publik: ${PUBLIC_URL})`);
});
