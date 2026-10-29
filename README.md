# Swavina — Smart Warm Vibration Activation (Flutter)

Aplikasi pasien untuk terapi hangat + getar berbasis perangkat **ESP32** (kaus kaki terapi untuk pasien DM tipe 2).
Project ini adalah migrasi dari prototipe Expo/React Native `VasoSocks` ke **Flutter**. Backend Node.js tetap sama (folder `backend/`).

## Fitur

| Tab | Isi |
|-----|-----|
| Home | Progress harian, status perangkat BLE, terapi terakhir, ringkasan mingguan |
| Therapy | Slider durasi/suhu/getar, timer sesi, start/stop via BLE, scan & connect ESP32 |
| Schedule | Buat / ubah / hapus jadwal terapi, tombol *Start* langsung membuka Therapy |
| History | Riwayat sesi dari server (tarik untuk refresh, hapus) |
| Profile | Data pribadi, tubuh, kesehatan, foto profil, logout |

Sesi yang selesai disimpan ke **SQLite lokal** (offline) lalu dikirim ke server bila online.

## Struktur

```
swavina/
├── lib/
│   ├── main.dart                  # MaterialApp, routes, AuthGate
│   ├── core/
│   │   ├── api.dart               # REST client + JWT (shared_preferences)
│   │   ├── ble_service.dart       # BLE ESP32 (flutter_blue_plus) — UUID ada di sini
│   │   ├── wifi_service.dart      # WiFi ESP8266 (provisioning AP + HTTP lokal)
│   │   ├── device_service.dart    # pilih transport aktif (BLE / WiFi) untuk layar
│   │   ├── local_db.dart          # SQLite lokal (sqflite)
│   │   ├── app_state.dart         # navigasi tab & parameter terapi dari jadwal
│   │   └── theme.dart             # warna & tema (light/dark mengikuti sistem)
│   ├── widgets/                   # CardBox, PrimaryButton, SwavinaScaffold (header berlogo)
│   └── screens/                   # login, register, home_shell, dashboard, therapy, schedule, history, profile
├── assets/images/                 # logo
├── backend/                       # API Node.js + SQLite (pasien + monitoring /api/admin)
├── admin/                         # PWA monitoring perawat & peneliti (Vite + React)
├── firmware/esp32_swavina_ble/    # sketch Arduino ESP32 untuk mode Bluetooth
├── firmware/esp8266_swavina/      # sketch Arduino ESP8266 untuk mode WiFi
├── setup.sh                       # generate android/ios + izin native + pub get
└── test/widget_test.dart
```

## Menjalankan

Prasyarat: Flutter SDK (>= 3.27), Android Studio / Xcode, Node.js >= 18.

```bash
# 1. Sekali saja: buat folder native & tambah izin Bluetooth
./setup.sh

# 2. Jalankan backend
cd backend && cp .env.example .env && npm install && npm run dev

# 3. Jalankan app (BLE hanya bisa di HP fisik)
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000/api
```

`API_BASE_URL` default `https://apiswavina.nurul-huda.net/api` (server produksi). Untuk backend lokal gunakan `http://10.0.2.2:3000/api` (emulator) atau IP lokal komputer
(satu WiFi) atau URL ngrok (`https://xxx.ngrok-free.app/api`).

## Koneksi WiFi (ESP8266)

Selain Bluetooth (ESP32), perangkat ESP8266 bisa dihubungkan lewat WiFi. Buka Therapy → ikon pengaturan → tab **WiFi** → **Setup WiFi Perangkat**:

1. HP masuk ke WiFi perangkat `Swavina-XXXX` (password `swavina123`) lewat Pengaturan.
2. Aplikasi menampilkan WiFi yang terlihat perangkat; pilih WiFi rumah & isi password → dikirim ke `192.168.4.1`.
3. Perangkat masuk ke WiFi rumah (IP dibaca dari `/status`), lalu AP-nya mati sendiri.
4. HP kembali ke WiFi rumah → **Cari Perangkat** (IP tersimpan → `swavina.local` → IP manual).

SSID/password juga bisa diganti tanpa aplikasi lewat halaman web perangkat: `http://192.168.4.1` (saat tersambung ke AP perangkat) atau `http://swavina.local` / `http://<ip>` (di WiFi rumah). Jika WiFi baru gagal, perangkat kembali ke WiFi lama dan AP `Swavina-XXXX` tetap terbuka untuk mencoba lagi.

Saat terapi berjalan, tab Therapy menampilkan **Sensor Realtime** kaki kiri & kanan (suhu °C, getaran Hz) dibanding target; aplikasi membaca `GET /status` tiap detik (`sensors.left/right`). Firmware saat ini **mensimulasikan** sensor (`SIMULATE_SENSORS 1` di `firmware/esp8266_swavina/sensors.h`, ditandai label *Simulasi* di aplikasi) — ganti ke `0` dan isi fungsi pembacaan saat sensor sungguhan terpasang.

Perintah terapi dikirim ke `POST http://<ip>/command` dengan JSON yang sama seperti BLE. Firmware contoh & daftar endpoint:
`firmware/esp8266_swavina/esp8266_swavina.ino` (ESP8266 core + ArduinoJson v7). Konstanta sisi aplikasi ada di `lib/core/wifi_service.dart`.

## Aplikasi Monitoring (Perawat & Peneliti)

PWA di folder `admin/` (Vite + React) memakai backend & database yang sama dengan aplikasi pasien, sesuai rancangan arsitektur dan flowchart peneliti/perawat di `../docs`:

| Menu | Isi |
|------|-----|
| Dashboard | Jumlah responden per kelompok, rata-rata kepatuhan, alert terbuka, jadwal kunjungan pre/post-test |
| Pasien | Pilih kelompok **Intervensi / Kontrol** → daftar responden (kepatuhan, pre/post, alert) → detail: data karakteristik, hubungkan akun aplikasi, **atur jadwal terapi** (langsung muncul di app pasien), **kepatuhan & riwayat sesi**, **input pengukuran** (ABI dari tekanan Doppler, NTSS-6, DN4, NRS, suhu kulit per titik, laktat), **formulir keamanan** |
| Alert | Alert klinis otomatis → detail → hubungi pasien (telepon/WhatsApp) → catat tindak lanjut |
| Analisis | Perbandingan pre–post dan intervensi–kontrol (rerata ± SD, Δ) + **ekspor CSV** (dataset 1 baris/responden untuk SPSS/SmartPLS, pengukuran, log sesi, keamanan) |

Alert otomatis (`backend/src/services/alerts.js`): suhu terapi > 40°C, asimetri suhu kulit kiri–kanan ≥ 2,2°C, ABI ≤ 0,90, NRS naik ≥ 2 dari pre-test, kejadian tidak diinginkan, tidak terapi ≥ 3 hari, kepatuhan < 80%.
Kepatuhan = sesi selesai ÷ sesi direncanakan (default 28 = 1 sesi/hari × 4 minggu) × 100%; sesi yang dihentikan sebelum durasi target tidak dihitung selesai.

```bash
# Akun tenaga kesehatan (peran: nurse | researcher | admin)
cd backend && npm run create-staff -- perawat@puskesmas.id "admin123" "Nama Perawat" nurse

# Ganti password akun mana pun (pasien/staf) tanpa mengubah data lain
cd backend && npm run reset-password -- perawat@puskesmas.id "passwordBaru123"

# Data uji: sesi terapi simulasi (sensor suhu & getar) untuk akun pasien, ditandai transport "simulasi"
cd backend && npm run simulate-sessions -- pasien@contoh.id 14     # 14 hari terakhir
cd backend && npm run simulate-sessions -- pasien@contoh.id --hapus # hapus lagi

# Build sekali → disajikan backend di root: http://localhost:3000/  (API tetap di /api, dokumentasi di /docs)
cd admin && npm install && npm run build

# Atau mode pengembangan (hot reload, /api diteruskan ke backend :3000)
cd admin && npm run dev     # http://localhost:5173/
```

## Konfigurasi ESP32

UUID service/characteristic dan prefix nama perangkat (`Swavina`) ada di `lib/core/ble_service.dart` — samakan dengan firmware.
Perintah dikirim sebagai JSON: `{"cmd":"start","temp":38,"vib":45,"dur":20}` dan `{"cmd":"stop"}`.

Firmware contoh: `firmware/esp32_swavina_ble/esp32_swavina_ble.ino` (board *ESP32 Dev Module*, core esp32 3.x + ArduinoJson v7). Perangkat mengiklankan diri sebagai `Swavina-XXXX`, status (≤ 20 byte, mis. `Berjalan 19:40`, `Selesai`) dikirim lewat notify tiap detik saat terapi berjalan. Pemanas di GPIO 25, motor getar di GPIO 26.

```bash
arduino-cli compile --fqbn esp32:esp32:esp32 --upload -p /dev/cu.usbserial-XXXX firmware/esp32_swavina_ble
```

## Padanan Expo → Flutter

| Expo / React Native | Flutter |
|---|---|
| expo-router (tabs, stack) | `Navigator` + `NavigationBar` + `IndexedStack` |
| AsyncStorage | shared_preferences |
| react-native-ble-plx | flutter_blue_plus |
| expo-sqlite | sqflite |
| expo-image-picker | image_picker |
| @react-native-community/slider / datetimepicker | `Slider`, `showDatePicker`, `showTimePicker` |
| expo-haptics | `HapticFeedback` |

## Catatan

- Bundle ID / package berubah dari `com.dariemana.VasoSocks` menjadi `com.dariemana.swavina` (ubah di `setup.sh` bila ingin tetap memakai yang lama).
- `expo-notifications` (`utils/notifications.tsx`) tidak dipindahkan karena tidak dipakai di layar mana pun; tambahkan `flutter_local_notifications` bila pengingat terapi dibutuhkan.
- Format tanggal/jam jadwal & riwayat kini seragam (`yyyy-MM-dd`, `HH:mm:ss`); `backend/src/routes/dashboard.js` disesuaikan agar "progress hari ini" tetap cocok. Data lama berformat locale tidak ikut terhitung di progress harian.
