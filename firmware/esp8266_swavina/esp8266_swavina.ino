/*
 * Swavina — firmware ESP8266 (koneksi WiFi)
 *
 * Alur:
 *  1. Belum ada WiFi tersimpan → perangkat membuat Access Point "Swavina-XXXX"
 *     (password: swavina123, IP 192.168.4.1).
 *  2. Aplikasi mengirim SSID & password WiFi rumah ke POST /wifi.
 *  3. Perangkat masuk ke WiFi rumah, IP bisa dibaca di GET /status,
 *     lalu AP dimatikan otomatis setelah 60 detik.
 *  4. Di WiFi rumah perangkat bisa diakses lewat http://swavina.local
 *     atau IP-nya. Kredensial disimpan di flash (bertahan setelah restart).
 *
 * Halaman web: buka http://192.168.4.1 (saat tersambung ke AP perangkat) atau
 * http://swavina.local untuk melihat status & mengganti SSID/password WiFi.
 * Jika WiFi baru gagal, perangkat kembali ke WiFi lama dan AP tetap terbuka.
 *
 * API (JSON):
 *  GET  /         → halaman web pengaturan WiFi
 *  GET  /info     → {"name","id","mode","fw"}
 *  GET  /scan     → {"networks":[{"ssid","rssi","secure"}]}
 *  POST /wifi     ← {"ssid","password"} (JSON / form)  → {"ok":true}
 *  GET  /status   → {"wifi":"idle|connecting|connected|failed","ip","ssid","ap","therapy","remaining",
 *                     "target":{"temp","vib"},
 *                     "sensors":{"simulated","left":{"temp","vib"},"right":{"temp","vib"}}}
 *  POST /command  ← {"cmd":"start","temp":38,"vib":45,"dur":20} | {"cmd":"stop"}
 *  POST /reset    → hapus WiFi tersimpan & restart ke mode AP
 *
 * Library: ESP8266 core (board "NodeMCU 1.0" / "LOLIN D1 mini") + ArduinoJson v7.
 */

#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <ESP8266mDNS.h>
#include <ArduinoJson.h>

#include "sensors.h"
#include "web_page.h"

// ── Konfigurasi ─────────────────────────────────────────────────────────────
const char *AP_PASSWORD = "swavina123";  // min. 8 karakter
const char *MDNS_NAME = "swavina";       // → swavina.local
const char *FW_VERSION = "1.2.0";

const int TEMP_MIN = 30;  // °C
const int TEMP_MAX = 40;  // °C, batas aman — samakan dengan maxTemperature di aplikasi

const uint8_t HEATER_PIN = D1;  // PWM ke driver MOSFET pemanas
const uint8_t VIB_PIN = D2;     // PWM ke driver motor getar
// ────────────────────────────────────────────────────────────────────────────

ESP8266WebServer server(80);

String deviceId;     // 4 digit hex terakhir dari chip ID
String deviceName;   // "Swavina-XXXX"
String wifiState = "idle";

bool pendingConnect = false;
String pendingSsid, pendingPassword;
unsigned long connectStartedAt = 0;
unsigned long failedAt = 0;
String prevSsid, prevPassword;  // WiFi lama, dipakai lagi jika WiFi baru gagal
unsigned long apOffAt = 0;
bool mdnsStarted = false;

bool therapyRunning = false;
unsigned long therapyEndsAt = 0;
int therapyTemp = 0, therapyVib = 0;

/* ===== TERAPI ===== */
void stopTherapy() {
  therapyRunning = false;
  analogWrite(HEATER_PIN, 0);
  analogWrite(VIB_PIN, 0);
  sensors::setTarget(false, 0, 0);
}

void startTherapy(int temp, int vib, int dur) {
  // Pemetaan sederhana parameter → duty PWM. Ganti dengan kontrol suhu
  // tertutup (mis. PID + sensor DS18B20) sesuai hardware.
  // Suhu dibatasi maks. TEMP_MAX °C walau aplikasi mengirim nilai lebih tinggi.
  temp = constrain(temp, TEMP_MIN, TEMP_MAX);
  int heatDuty = map(temp, 30, 45, 300, 1023);
  int vibDuty = map(constrain(vib, 30, 60), 30, 60, 400, 1023);
  analogWrite(HEATER_PIN, heatDuty);
  analogWrite(VIB_PIN, vibDuty);
  therapyRunning = true;
  therapyEndsAt = millis() + (unsigned long)constrain(dur, 1, 60) * 60000UL;
  therapyTemp = temp;
  therapyVib = constrain(vib, 30, 60);
  sensors::setTarget(true, therapyTemp, therapyVib);
}

/* ===== HELPER ===== */
void sendJson(int code, JsonDocument &doc) {
  String out;
  serializeJson(doc, out);
  server.send(code, "application/json", out);
}

void sendOk() {
  JsonDocument doc;
  doc["ok"] = true;
  sendJson(200, doc);
}

void sendError(int code, const char *msg) {
  JsonDocument doc;
  doc["ok"] = false;
  doc["error"] = msg;
  sendJson(code, doc);
}

bool readBody(JsonDocument &doc) {
  return deserializeJson(doc, server.arg("plain")) == DeserializationError::Ok;
}

void startAccessPoint() {
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAPConfig(IPAddress(192, 168, 4, 1), IPAddress(192, 168, 4, 1), IPAddress(255, 255, 255, 0));
  WiFi.softAP(deviceName.c_str(), AP_PASSWORD);
  apOffAt = 0;
  Serial.printf("AP aktif: %s (%s)\n", deviceName.c_str(), WiFi.softAPIP().toString().c_str());
}

void startMdns() {
  if (mdnsStarted) return;
  if (MDNS.begin(MDNS_NAME)) {
    MDNS.addService("http", "tcp", 80);
    mdnsStarted = true;
  }
}

/* ===== ROUTES ===== */
void handleInfo() {
  JsonDocument doc;
  doc["name"] = deviceName;
  doc["id"] = deviceId;
  doc["mode"] = (WiFi.getMode() & WIFI_AP) ? "ap" : "sta";
  doc["fw"] = FW_VERSION;
  sendJson(200, doc);
}

void handleScan() {
  int n = WiFi.scanNetworks();
  JsonDocument doc;
  JsonArray arr = doc["networks"].to<JsonArray>();
  for (int i = 0; i < n; i++) {
    JsonObject o = arr.add<JsonObject>();
    o["ssid"] = WiFi.SSID(i);
    o["rssi"] = WiFi.RSSI(i);
    o["secure"] = WiFi.encryptionType(i) != ENC_TYPE_NONE;
  }
  WiFi.scanDelete();
  sendJson(200, doc);
}

void handleRoot() {
  server.send_P(200, "text/html; charset=utf-8", WEB_PAGE);
}

void handleWifi() {
  String ssid, password;
  if (server.hasArg("ssid")) {  // form HTML biasa
    ssid = server.arg("ssid");
    password = server.arg("password");
  } else {
    JsonDocument body;
    if (readBody(body)) {
      ssid = body["ssid"] | "";
      password = body["password"] | "";
    }
  }
  ssid.trim();
  if (ssid.isEmpty() || ssid.length() > 32 || password.length() > 64) {
    sendError(400, "ssid wajib diisi (maks. 32 karakter), password maks. 64 karakter");
    return;
  }

  // Ganti WiFi saat sudah terhubung: simpan yang lama untuk fallback dan buka
  // AP agar perangkat tetap bisa dijangkau jika WiFi baru gagal.
  if (WiFi.status() == WL_CONNECTED) {
    prevSsid = WiFi.SSID();
    prevPassword = WiFi.psk();
  }
  if (!(WiFi.getMode() & WIFI_AP)) startAccessPoint();
  apOffAt = 0;

  pendingSsid = ssid;
  pendingPassword = password;
  pendingConnect = true;  // dieksekusi di loop() setelah respons terkirim
  wifiState = "connecting";
  failedAt = 0;
  sendOk();
}

void addFoot(JsonObject o, const FootReading &f) {
  if (!isnan(f.temp)) o["temp"] = serialized(String(f.temp, 1));
  if (!isnan(f.vib)) o["vib"] = serialized(String(f.vib, 1));
}

void handleStatus() {
  JsonDocument doc;
  doc["wifi"] = wifiState;
  if (WiFi.status() == WL_CONNECTED) {
    doc["ip"] = WiFi.localIP().toString();
    doc["ssid"] = WiFi.SSID();
  }
  doc["ap"] = (WiFi.getMode() & WIFI_AP) != 0;
  doc["therapy"] = therapyRunning ? "running" : "idle";
  if (therapyRunning) {
    doc["remaining"] = (therapyEndsAt - millis()) / 1000;
    doc["target"]["temp"] = therapyTemp;
    doc["target"]["vib"] = therapyVib;
  }
  JsonObject sens = doc["sensors"].to<JsonObject>();
  sens["simulated"] = SIMULATE_SENSORS == 1;
  addFoot(sens["left"].to<JsonObject>(), leftFoot);
  addFoot(sens["right"].to<JsonObject>(), rightFoot);
  sendJson(200, doc);
}

void handleCommand() {
  JsonDocument body;
  if (!readBody(body)) {
    sendError(400, "JSON tidak valid");
    return;
  }
  String cmd = body["cmd"] | "";
  if (cmd == "start") {
    startTherapy(body["temp"] | 38, body["vib"] | 45, body["dur"] | 20);
  } else if (cmd == "stop") {
    stopTherapy();
  } else {
    sendError(400, "cmd tidak dikenal");
    return;
  }
  sendOk();
}

void handleReset() {
  sendOk();
  delay(300);
  WiFi.disconnect(true);  // hapus kredensial tersimpan
  delay(300);
  ESP.restart();
}

/* ===== SETUP / LOOP ===== */
void setup() {
  randomSeed(RANDOM_REG32);
  Serial.begin(115200);
  pinMode(HEATER_PIN, OUTPUT);
  pinMode(VIB_PIN, OUTPUT);
  analogWriteRange(1023);
  stopTherapy();

  char id[5];
  snprintf(id, sizeof(id), "%04X", (unsigned)(ESP.getChipId() & 0xFFFF));
  deviceId = id;
  deviceName = "Swavina-" + deviceId;

  WiFi.persistent(true);
  WiFi.setAutoReconnect(true);
  WiFi.hostname(deviceName);
  WiFi.mode(WIFI_STA);

  // Coba WiFi tersimpan dulu (15 detik), jika gagal buka Access Point.
  if (WiFi.SSID().length() > 0) {
    WiFi.begin();
    unsigned long t = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - t < 15000) delay(250);
  }
  if (WiFi.status() == WL_CONNECTED) {
    wifiState = "connected";
    Serial.printf("Terhubung ke %s, IP %s\n", WiFi.SSID().c_str(), WiFi.localIP().toString().c_str());
    startMdns();
  } else {
    startAccessPoint();
  }

  server.on("/", HTTP_GET, handleRoot);
  server.on("/info", HTTP_GET, handleInfo);
  server.on("/scan", HTTP_GET, handleScan);
  server.on("/wifi", HTTP_POST, handleWifi);
  server.on("/status", HTTP_GET, handleStatus);
  server.on("/command", HTTP_POST, handleCommand);
  server.on("/reset", HTTP_POST, handleReset);
  server.onNotFound([]() { sendError(404, "not found"); });
  server.begin();
}

void loop() {
  server.handleClient();
  if (mdnsStarted) MDNS.update();

  // Mulai koneksi ke WiFi rumah setelah respons /wifi terkirim.
  if (pendingConnect) {
    pendingConnect = false;
    delay(200);
    WiFi.begin(pendingSsid.c_str(), pendingPassword.c_str());
    connectStartedAt = millis();
  }

  if (wifiState == "connecting") {
    wl_status_t st = WiFi.status();
    if (st == WL_CONNECTED) {
      wifiState = "connected";
      prevSsid = "";
      prevPassword = "";
      startMdns();
      apOffAt = millis() + 60000;  // beri waktu aplikasi membaca IP
      Serial.printf("Terhubung, IP %s\n", WiFi.localIP().toString().c_str());
    } else if (st == WL_CONNECT_FAILED || st == WL_NO_SSID_AVAIL || st == WL_WRONG_PASSWORD ||
               millis() - connectStartedAt > 20000) {
      wifiState = "failed";
      failedAt = millis();
      WiFi.disconnect(false);
      // Kembali ke WiFi lama (juga menyimpannya lagi sebagai default).
      if (prevSsid.length() > 0) WiFi.begin(prevSsid.c_str(), prevPassword.c_str());
      Serial.println("Gagal masuk WiFi baru");
    }
  }

  // Setelah gagal & berhasil kembali ke WiFi lama: status normal lagi, AP
  // ditutup setelah 2 menit (cukup untuk membaca pesan gagal dan mencoba lagi).
  if (wifiState == "failed" && prevSsid.length() > 0 && WiFi.status() == WL_CONNECTED &&
      millis() - failedAt > 15000) {
    wifiState = "connected";
    prevSsid = "";
    prevPassword = "";
    apOffAt = millis() + 120000;
  }

  // Matikan AP setelah berhasil masuk ke WiFi rumah.
  if (apOffAt && millis() > apOffAt) {
    apOffAt = 0;
    WiFi.softAPdisconnect(true);
    WiFi.mode(WIFI_STA);
  }

  // Jika WiFi tersimpan hilang lama (mis. ganti router), buka lagi AP.
  static unsigned long lostSince = 0;
  if (wifiState == "connected" && WiFi.status() != WL_CONNECTED) {
    if (!lostSince) lostSince = millis();
    if (millis() - lostSince > 60000 && !(WiFi.getMode() & WIFI_AP)) startAccessPoint();
  } else {
    lostSince = 0;
  }

  if (therapyRunning && (long)(millis() - therapyEndsAt) >= 0) stopTherapy();
  sensors::update();
}
