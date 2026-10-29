#!/usr/bin/env bash
# Setup sekali jalan untuk project Flutter Swavina.
# Membuat folder native android/ & ios/, menambah izin Bluetooth/kamera, lalu `flutter pub get`.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter belum terpasang / belum ada di PATH. Lihat https://docs.flutter.dev/get-started/install"
  exit 1
fi

# 1) Generate platform native (tidak menimpa lib/, pubspec.yaml, test/)
flutter create --org com.dariemana --project-name swavina --platforms=android,ios .

# 2) Patch izin & konfigurasi native (idempotent)
python3 - <<'PY'
import re, pathlib

# ---------- Android ----------
manifest = pathlib.Path("android/app/src/main/AndroidManifest.xml")
if manifest.exists():
    s = manifest.read_text()
    if "BLUETOOTH_SCAN" not in s:
        perms = '''    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>
    <uses-feature android:name="android.hardware.bluetooth_le" android:required="false"/>
'''
        s = re.sub(r"(<manifest[^>]*>\s*)", lambda m: m.group(1) + "\n" + perms, s, count=1)
    if "usesCleartextTraffic" not in s:
        # izinkan http:// ke backend lokal saat development
        s = s.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
    s = s.replace('android:label="swavina"', 'android:label="Swavina"')
    manifest.write_text(s)
    print("patched", manifest)

# ---------- iOS ----------
plist = pathlib.Path("ios/Runner/Info.plist")
if plist.exists():
    s = plist.read_text()
    if "NSBluetoothAlwaysUsageDescription" not in s:
        add = '''	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>Swavina membutuhkan Bluetooth untuk terhubung ke perangkat terapi ESP32.</string>
	<key>NSBluetoothPeripheralUsageDescription</key>
	<string>Swavina membutuhkan Bluetooth untuk terhubung ke perangkat terapi ESP32.</string>
	<key>NSCameraUsageDescription</key>
	<string>Swavina membutuhkan kamera untuk mengambil foto profil.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Swavina membutuhkan akses galeri untuk memilih foto profil.</string>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsLocalNetworking</key>
		<true/>
	</dict>
'''
        idx = s.rfind("</dict>")
        s = s[:idx] + add + s[idx:]
        plist.write_text(s)
        print("patched", plist)
PY

# 3) Dependensi
flutter pub get

echo
echo "Selesai. Jalankan backend (cd backend && npm install && npm run dev), lalu:"
echo "  flutter run --dart-define=API_BASE_URL=http://<IP-komputer>:3000/api"
