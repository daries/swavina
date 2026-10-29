const swaggerJsdoc = require("swagger-jsdoc");

const options = {
  definition: {
    openapi: "3.0.0",
    info: {
      title: "Swavina API",
      version: "1.0.0",
      description: "Backend API untuk aplikasi Swavina — Smart Warm Vibration Activation. Mengontrol perangkat terapi ESP32 berbasis suhu hangat dan getaran.",
    },
    servers: [
      { url: `${process.env.PUBLIC_URL || "https://apiswavina.nurul-huda.net"}/api`, description: "Production" },
      { url: "http://localhost:3000/api", description: "Local Development" },
    ],
    components: {
      securitySchemes: {
        bearerAuth: {
          type: "http",
          scheme: "bearer",
          bearerFormat: "JWT",
        },
      },
      schemas: {
        Error: {
          type: "object",
          properties: {
            message: { type: "string", example: "Pesan error" },
          },
        },
        LoginRequest: {
          type: "object",
          required: ["email", "password"],
          properties: {
            email: { type: "string", format: "email", example: "user@swavina.com" },
            password: { type: "string", example: "123456" },
          },
        },
        RegisterRequest: {
          type: "object",
          required: ["email", "password"],
          properties: {
            email: { type: "string", format: "email", example: "user@swavina.com" },
            password: { type: "string", example: "123456" },
            name: { type: "string", example: "Budi Santoso" },
          },
        },
        AuthResponse: {
          type: "object",
          properties: {
            token: { type: "string", example: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." },
            userId: { type: "integer", example: 1 },
          },
        },
        TherapySession: {
          type: "object",
          properties: {
            id: { type: "integer", example: 1 },
            user_id: { type: "integer", example: 1 },
            date: { type: "string", example: "13/6/2026" },
            start_time: { type: "string", example: "08:00:00" },
            duration: { type: "integer", example: 20, description: "Durasi dalam menit" },
            temperature: { type: "integer", example: 38, description: "Suhu dalam °C (30-40)" },
            vibration: { type: "integer", example: 45, description: "Frekuensi getar dalam Hz (30-60)" },
            created_at: { type: "string", example: "2026-06-13 08:00:00" },
          },
        },
        TherapyRequest: {
          type: "object",
          required: ["duration", "temperature", "vibration"],
          properties: {
            date: { type: "string", example: "13/6/2026" },
            start_time: { type: "string", example: "08:00:00" },
            duration: { type: "integer", example: 20 },
            temperature: { type: "integer", example: 38 },
            vibration: { type: "integer", example: 45 },
          },
        },
        Schedule: {
          type: "object",
          properties: {
            id: { type: "integer", example: 1 },
            user_id: { type: "integer", example: 1 },
            date: { type: "string", example: "13/6/2026" },
            time: { type: "string", example: "08:00:00" },
            duration: { type: "integer", example: 30 },
            temperature: { type: "integer", example: 38 },
            vibration: { type: "integer", example: 45 },
            created_at: { type: "string", example: "2026-06-13 07:00:00" },
          },
        },
        ScheduleRequest: {
          type: "object",
          required: ["date", "time", "duration"],
          properties: {
            date: { type: "string", example: "13/6/2026" },
            time: { type: "string", example: "08:00:00" },
            duration: { type: "integer", example: 30 },
            temperature: { type: "integer", example: 38 },
            vibration: { type: "integer", example: 45 },
          },
        },
        Profile: {
          type: "object",
          properties: {
            id: { type: "integer", example: 1 },
            user_id: { type: "integer", example: 1 },
            name: { type: "string", example: "Budi Santoso" },
            birth_date: { type: "string", example: "1990-06-12" },
            height: { type: "number", example: 170, description: "Tinggi badan dalam cm" },
            height_date: { type: "string", example: "2026-01-01" },
            weight: { type: "number", example: 68, description: "Berat badan dalam kg" },
            weight_date: { type: "string", example: "2026-01-01" },
            blood_sugar: { type: "string", example: "120", description: "Gula darah dalam mg/dL" },
            blood_sugar_date: { type: "string", example: "2026-01-01" },
            blood_pressure: { type: "string", example: "120/80", description: "Tekanan darah dalam mmHg" },
            blood_pressure_date: { type: "string", example: "2026-01-01" },
            profile_image: { type: "string", nullable: true, example: null },
          },
        },
        Dashboard: {
          type: "object",
          properties: {
            today_duration: { type: "integer", example: 20, description: "Total menit terapi hari ini" },
            daily_target: { type: "integer", example: 30, description: "Target harian dalam menit" },
            last_session: {
              nullable: true,
              allOf: [{ $ref: "#/components/schemas/TherapySession" }],
            },
            weekly_sessions: { type: "integer", example: 5, description: "Jumlah sesi 7 hari terakhir" },
            weekly_duration: { type: "integer", example: 120, description: "Total menit 7 hari terakhir" },
          },
        },
      },
    },
    security: [{ bearerAuth: [] }],
    tags: [
      { name: "Auth", description: "Autentikasi pengguna" },
      { name: "Dashboard", description: "Data ringkasan & progress terapi" },
      { name: "Therapy", description: "Riwayat sesi terapi" },
      { name: "Schedule", description: "Jadwal terapi" },
      { name: "Profile", description: "Data profil pengguna" },
    ],
    paths: {
      "/auth/register": {
        post: {
          tags: ["Auth"],
          summary: "Daftar akun baru",
          security: [],
          requestBody: {
            required: true,
            content: { "application/json": { schema: { $ref: "#/components/schemas/RegisterRequest" } } },
          },
          responses: {
            201: { description: "Berhasil register", content: { "application/json": { schema: { $ref: "#/components/schemas/AuthResponse" } } } },
            400: { description: "Field wajib kosong", content: { "application/json": { schema: { $ref: "#/components/schemas/Error" } } } },
            409: { description: "Email sudah terdaftar", content: { "application/json": { schema: { $ref: "#/components/schemas/Error" } } } },
          },
        },
      },
      "/auth/login": {
        post: {
          tags: ["Auth"],
          summary: "Login dan dapatkan token JWT",
          security: [],
          requestBody: {
            required: true,
            content: { "application/json": { schema: { $ref: "#/components/schemas/LoginRequest" } } },
          },
          responses: {
            200: { description: "Login berhasil", content: { "application/json": { schema: { $ref: "#/components/schemas/AuthResponse" } } } },
            400: { description: "Field wajib kosong" },
            401: { description: "Email atau password salah", content: { "application/json": { schema: { $ref: "#/components/schemas/Error" } } } },
          },
        },
      },
      "/auth/me": {
        get: {
          tags: ["Auth"],
          summary: "Info user yang sedang login",
          responses: {
            200: {
              description: "Data user",
              content: {
                "application/json": {
                  schema: {
                    type: "object",
                    properties: {
                      id: { type: "integer" },
                      email: { type: "string" },
                      created_at: { type: "string" },
                    },
                  },
                },
              },
            },
            401: { description: "Unauthorized" },
          },
        },
      },
      "/dashboard": {
        get: {
          tags: ["Dashboard"],
          summary: "Progress harian dan ringkasan mingguan",
          responses: {
            200: { description: "Data dashboard", content: { "application/json": { schema: { $ref: "#/components/schemas/Dashboard" } } } },
            401: { description: "Unauthorized" },
          },
        },
      },
      "/therapy": {
        get: {
          tags: ["Therapy"],
          summary: "Ambil semua riwayat terapi",
          responses: {
            200: {
              description: "Daftar riwayat terapi",
              content: { "application/json": { schema: { type: "array", items: { $ref: "#/components/schemas/TherapySession" } } } },
            },
            401: { description: "Unauthorized" },
          },
        },
        post: {
          tags: ["Therapy"],
          summary: "Simpan sesi terapi selesai",
          requestBody: {
            required: true,
            content: { "application/json": { schema: { $ref: "#/components/schemas/TherapyRequest" } } },
          },
          responses: {
            201: { description: "Berhasil disimpan", content: { "application/json": { schema: { type: "object", properties: { id: { type: "integer" } } } } } },
            400: { description: "Field wajib kosong" },
            401: { description: "Unauthorized" },
          },
        },
      },
      "/therapy/{id}": {
        delete: {
          tags: ["Therapy"],
          summary: "Hapus riwayat terapi",
          parameters: [{ name: "id", in: "path", required: true, schema: { type: "integer" }, description: "ID riwayat terapi" }],
          responses: {
            200: { description: "Berhasil dihapus" },
            401: { description: "Unauthorized" },
            404: { description: "Data tidak ditemukan" },
          },
        },
      },
      "/schedule": {
        get: {
          tags: ["Schedule"],
          summary: "Ambil semua jadwal terapi",
          responses: {
            200: { description: "Daftar jadwal", content: { "application/json": { schema: { type: "array", items: { $ref: "#/components/schemas/Schedule" } } } } },
            401: { description: "Unauthorized" },
          },
        },
        post: {
          tags: ["Schedule"],
          summary: "Buat jadwal terapi baru",
          requestBody: {
            required: true,
            content: { "application/json": { schema: { $ref: "#/components/schemas/ScheduleRequest" } } },
          },
          responses: {
            201: { description: "Berhasil dibuat", content: { "application/json": { schema: { type: "object", properties: { id: { type: "integer" } } } } } },
            400: { description: "Field wajib kosong" },
            401: { description: "Unauthorized" },
          },
        },
      },
      "/schedule/{id}": {
        put: {
          tags: ["Schedule"],
          summary: "Update jadwal terapi",
          parameters: [{ name: "id", in: "path", required: true, schema: { type: "integer" } }],
          requestBody: {
            required: true,
            content: { "application/json": { schema: { $ref: "#/components/schemas/ScheduleRequest" } } },
          },
          responses: {
            200: { description: "Berhasil diupdate" },
            401: { description: "Unauthorized" },
            404: { description: "Jadwal tidak ditemukan" },
          },
        },
        delete: {
          tags: ["Schedule"],
          summary: "Hapus jadwal terapi",
          parameters: [{ name: "id", in: "path", required: true, schema: { type: "integer" } }],
          responses: {
            200: { description: "Berhasil dihapus" },
            401: { description: "Unauthorized" },
            404: { description: "Jadwal tidak ditemukan" },
          },
        },
      },
      "/profile": {
        get: {
          tags: ["Profile"],
          summary: "Ambil data profil pengguna",
          responses: {
            200: { description: "Data profil", content: { "application/json": { schema: { $ref: "#/components/schemas/Profile" } } } },
            401: { description: "Unauthorized" },
            404: { description: "Profile tidak ditemukan" },
          },
        },
        put: {
          tags: ["Profile"],
          summary: "Update data profil pengguna",
          requestBody: {
            required: true,
            content: { "application/json": { schema: { $ref: "#/components/schemas/Profile" } } },
          },
          responses: {
            200: { description: "Berhasil diupdate" },
            401: { description: "Unauthorized" },
          },
        },
      },
    },
  },
  apis: [],
};

module.exports = swaggerJsdoc(options);
