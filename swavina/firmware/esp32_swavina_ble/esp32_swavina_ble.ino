/*
 * Swavina — firmware ESP32 (koneksi Bluetooth Low Energy)
 *
 * Perangkat mengiklankan diri sebagai "Swavina-XXXX" dengan service UUID
 * di bawah. Aplikasi (lib/core/ble_service.dart) scan → connect → menulis
 * perintah JSON ke characteristic COMMAND dan menerima status lewat notify
 * characteristic STATUS.
 *
 * GATT:
 *  Service  4fafc201-1fb5-459e-8fcc-c5c9c331914b
 *   COMMAND beb5483e-36e1-4688-b7f5-ea07361b26a8  (write / write without response)
 *           {"cmd":"start","temp":38,"vib":45,"dur":20} | {"cmd":"stop"} | {"cmd":"status"}
 *   STATUS  6e400003-b5a3-f393-e0a9-e50e24dcca9e  (read / notify, teks ≤ 20 byte)
 *           "Siap" | "Berjalan 19:40" | "Selesai" | "Berhenti" | pesan error
 *
 * Board: ESP32 Dev Module (core esp32 3.x) + ArduinoJson v7.
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>

// ── Samakan dengan lib/core/ble_service.dart ────────────────────────────────
#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_COMMAND_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_STATUS_UUID "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
const char *NAME_PREFIX = "Swavina";  // aplikasi mencari nama berawalan ini
// ────────────────────────────────────────────────────────────────────────────

const int TEMP_MIN = 30;  // °C
const int TEMP_MAX = 40;  // °C, batas aman — samakan dengan maxTemperature di aplikasi

const uint8_t HEATER_PIN = 25;  // PWM ke driver MOSFET pemanas
const uint8_t VIB_PIN = 26;     // PWM ke driver motor getar
const uint8_t LED_PIN = 2;      // LED onboard: nyala saat terhubung
const uint32_t PWM_FREQ = 5000;
const uint8_t PWM_BITS = 10;    // duty 0–1023

BLEServer *server = nullptr;
BLECharacteristic *statusChar = nullptr;
String deviceName;

volatile bool clientConnected = false;
bool restartAdvertising = false;

bool therapyRunning = false;
unsigned long therapyEndsAt = 0;
unsigned long lastNotifyAt = 0;

// Perintah ditulis dari task BLE; dieksekusi di loop() agar aman.
String pendingCommand;
portMUX_TYPE cmdMux = portMUX_INITIALIZER_UNLOCKED;

/* ===== STATUS ===== */
void notifyStatus(const String &text) {
  if (!statusChar) return;
  statusChar->setValue(text.c_str());
  if (clientConnected) statusChar->notify();
  Serial.println("Status: " + text);
}

String runningText() {
  long left = therapyRunning ? (long)(therapyEndsAt - millis()) / 1000 : 0;
  if (left < 0) left = 0;
  char buf[21];
  snprintf(buf, sizeof(buf), "Berjalan %02ld:%02ld", left / 60, left % 60);
  return buf;
}

/* ===== TERAPI ===== */
void stopOutputs() {
  ledcWrite(HEATER_PIN, 0);
  ledcWrite(VIB_PIN, 0);
}

void startTherapy(int temp, int vib, int dur) {
  // Pemetaan sederhana parameter → duty PWM. Ganti dengan kontrol suhu
  // tertutup (mis. PID + sensor DS18B20 / NTC) sesuai hardware.
  // Suhu dibatasi maks. TEMP_MAX °C walau aplikasi mengirim nilai lebih tinggi.
  temp = constrain(temp, TEMP_MIN, TEMP_MAX);
  int heatDuty = map(temp, 30, 45, 300, 1023);
  int vibDuty = map(constrain(vib, 30, 60), 30, 60, 400, 1023);
  ledcWrite(HEATER_PIN, heatDuty);
  ledcWrite(VIB_PIN, vibDuty);
  therapyRunning = true;
  therapyEndsAt = millis() + (unsigned long)constrain(dur, 1, 60) * 60000UL;
  notifyStatus(runningText());
  lastNotifyAt = millis();
}

void stopTherapy(const char *reason) {
  therapyRunning = false;
  stopOutputs();
  notifyStatus(reason);
}

void handleCommand(const String &raw) {
  JsonDocument doc;
  if (deserializeJson(doc, raw) != DeserializationError::Ok) {
    notifyStatus("JSON tidak valid");
    return;
  }
  String cmd = doc["cmd"] | "";
  if (cmd == "start") {
    startTherapy(doc["temp"] | 38, doc["vib"] | 45, doc["dur"] | 20);
  } else if (cmd == "stop") {
    stopTherapy("Berhenti");
  } else if (cmd == "status") {
    notifyStatus(therapyRunning ? runningText() : String("Siap"));
  } else {
    notifyStatus("Cmd tidak dikenal");
  }
}

/* ===== CALLBACK BLE ===== */
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *) override {
    clientConnected = true;
  }
  void onDisconnect(BLEServer *) override {
    clientConnected = false;
    restartAdvertising = true;  // agar bisa ditemukan lagi
  }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    String v = c->getValue();
    portENTER_CRITICAL(&cmdMux);
    pendingCommand = v;
    portEXIT_CRITICAL(&cmdMux);
  }
};

void startAdvertising() {
  BLEAdvertising *adv = BLEDevice::getAdvertising();

  // Paket iklan (maks. 31 byte): flags + service UUID 128-bit.
  BLEAdvertisementData advData;
  advData.setFlags(0x06);  // LE General Discoverable, BR/EDR tidak didukung
  advData.setCompleteServices(BLEUUID(SERVICE_UUID));
  adv->setAdvertisementData(advData);

  // Nama lengkap dikirim di scan response agar tidak terpotong.
  BLEAdvertisementData scanData;
  scanData.setName(deviceName);
  adv->setScanResponseData(scanData);

  adv->setMinPreferred(0x06);  // membantu koneksi di iPhone
  adv->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("Advertising sebagai " + deviceName);
}

/* ===== SETUP / LOOP ===== */
void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  ledcAttach(HEATER_PIN, PWM_FREQ, PWM_BITS);
  ledcAttach(VIB_PIN, PWM_FREQ, PWM_BITS);
  stopOutputs();

  uint64_t mac = ESP.getEfuseMac();
  char id[5];
  snprintf(id, sizeof(id), "%02X%02X", (unsigned)((mac >> 32) & 0xFF), (unsigned)((mac >> 40) & 0xFF));
  deviceName = String(NAME_PREFIX) + "-" + id;

  BLEDevice::init(deviceName.c_str());
  server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService *service = server->createService(SERVICE_UUID);

  BLECharacteristic *commandChar = service->createCharacteristic(
      CHAR_COMMAND_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  commandChar->setCallbacks(new CommandCallbacks());

  statusChar = service->createCharacteristic(
      CHAR_STATUS_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
#if defined(CONFIG_BLUEDROID_ENABLED)
  statusChar->addDescriptor(new BLE2902());  // NimBLE menambahkannya otomatis
#endif
  statusChar->setValue("Siap");

  service->start();
  startAdvertising();
}

void loop() {
  String cmd;
  portENTER_CRITICAL(&cmdMux);
  if (pendingCommand.length()) {
    cmd = pendingCommand;
    pendingCommand = "";
  }
  portEXIT_CRITICAL(&cmdMux);
  if (cmd.length()) {
    Serial.println("Perintah: " + cmd);
    handleCommand(cmd);
  }

  if (restartAdvertising) {
    restartAdvertising = false;
    delay(300);  // beri waktu stack BLE menyelesaikan disconnect
    startAdvertising();
  }

  if (therapyRunning) {
    if ((long)(millis() - therapyEndsAt) >= 0) {
      stopTherapy("Selesai");
    } else if (millis() - lastNotifyAt >= 1000) {
      lastNotifyAt = millis();
      notifyStatus(runningText());
    }
  }

  digitalWrite(LED_PIN, clientConnected ? HIGH : LOW);
  delay(10);
}
