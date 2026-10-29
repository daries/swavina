import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Disajikan backend di root (/); saat dev, /api diteruskan ke backend lokal.
export default defineConfig({
  base: "/",
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": { target: process.env.API_TARGET || "https://apiswavina.nurul-huda.net", changeOrigin: true },
    },
  },
});
