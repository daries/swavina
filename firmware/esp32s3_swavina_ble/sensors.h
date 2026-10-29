#pragma once
#include <Arduino.h>
#include <Wire.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <Preferences.h>

// Sensor kaki kiri & kanan: suhu (°C) dan getaran (Hz).
//
// Sensor dideteksi otomatis — tidak perlu ganti firmware saat sensor dipasang:
//  - Suhu  : DS18B20, satu sensor per pin (kiri GPIO6, kanan GPIO7),
//            resistor pull-up 4,7 kΩ ke 3V3 di tiap pin data.
//  - Getar : MPU6050 / MPU6500 atau ADXL345 di I2C (SDA GPIO8, SCL GPIO9).
//            Kiri : MPU6050 AD0→GND (0x68) atau ADXL345 SDO→GND (0x53)
//            Kanan: MPU6050 AD0→3V3 (0x69) atau ADXL345 SDO→3V3 (0x1D)
// Sensor yang belum terpasang dicari ulang tiap 10 detik.
//
// Mode (tersimpan di flash, bisa diubah lewat BLE {"cmd":"sensor","mode":"..."}):
//  - auto: pakai sensor bila terdeteksi, selain itu simulasi (default)
//  - sim : selalu simulasi
//  - real: hanya sensor; sensor yang tidak terpasang tidak mengirim nilai

const uint8_t TEMP_PIN_LEFT = 6;
const uint8_t TEMP_PIN_RIGHT = 7;
const uint8_t I2C_SDA = 8;
const uint8_t I2C_SCL = 9;

struct FootReading {
  float temp;  // °C, NAN bila tidak ada
  float vib;   // Hz, NAN bila tidak ada
};

FootReading leftFoot = {31.5f, 0};
FootReading rightFoot = {31.2f, 0};

namespace sensors {

enum Mode : uint8_t { MODE_AUTO, MODE_SIM, MODE_REAL };
const char *MODE_NAMES[] = {"auto", "sim", "real"};

Mode mode = MODE_AUTO;
bool anySimulated = true;  // ada nilai simulasi di pembacaan terakhir

bool active = false;
float targetTemp = 0;
float targetVib = 0;
unsigned long lastUpdate = 0;
Preferences prefs;

/* ===== SIMULASI ===== */
const float SKIN_TEMP = 31.5f;  // suhu kulit kaki saat istirahat
FootReading simLeft = {SKIN_TEMP, 0};
FootReading simRight = {SKIN_TEMP - 0.3f, 0};

float noise(float amp) { return amp * (random(-1000, 1001) / 1000.0f); }

void simulateFoot(FootReading &f, float tauSec, float tempOffset, float vibFactor, float dt) {
  float goalTemp = active ? targetTemp + tempOffset : SKIN_TEMP + tempOffset;
  f.temp += (goalTemp - f.temp) * min(1.0f, dt / tauSec) + noise(0.04f);

  float goalVib = active ? targetVib * vibFactor : 0;
  f.vib += (goalVib - f.vib) * min(1.0f, dt / 0.8f);  // motor butuh ±1 detik
  if (active) f.vib += noise(0.6f);
  if (f.vib < 0.05f) f.vib = 0;
}

/* ===== SUHU: DS18B20 ===== */
struct TempProbe {
  OneWire wire;
  DallasTemperature ds;
  bool present = false;
  float value = NAN;
  TempProbe(uint8_t pin) : wire(pin), ds(&wire) {}

  void detect() {
    ds.begin();
    present = ds.getDeviceCount() > 0;
    if (present) {
      ds.setResolution(11);  // 0,125 °C, konversi ±375 ms
      ds.setWaitForConversion(false);
      ds.requestTemperatures();
    }
  }

  // Dipanggil tiap 1 detik: ambil hasil konversi sebelumnya lalu mulai lagi.
  void poll() {
    if (!present) return;
    float t = ds.getTempCByIndex(0);
    if (t == DEVICE_DISCONNECTED_C || t == 85.0f) {  // terlepas / belum siap
      present = false;
      value = NAN;
      return;
    }
    value = t;
    ds.requestTemperatures();
  }
};

TempProbe tempLeft(TEMP_PIN_LEFT);
TempProbe tempRight(TEMP_PIN_RIGHT);
unsigned long lastTempPoll = 0;
unsigned long lastTempDetect = 0;

/* ===== GETARAN: MPU6050 / ADXL345 (task terpisah, sampling ±500 Hz) ===== */
enum AccelType : uint8_t { ACCEL_NONE, ACCEL_MPU, ACCEL_ADXL };

struct VibProbe {
  uint8_t mpuAddr, adxlAddr;
  AccelType type = ACCEL_NONE;
  uint8_t addr = 0;
  uint8_t failures = 0;
  volatile float hz = NAN;
  // Hitung frekuensi: per sumbu buang komponen DC (gravitasi), lalu hitung
  // persilangan nol (dengan histeresis) pada sumbu dengan energi terbesar.
  float mean[3] = {0, 0, 0};
  float energy[3] = {0, 0, 0};
  uint16_t crossings[3] = {0, 0, 0};
  bool positive[3] = {false, false, false};
  uint16_t samples = 0;
  bool primed = false;

  VibProbe(uint8_t mpu, uint8_t adxl) : mpuAddr(mpu), adxlAddr(adxl) {}
};

VibProbe vibLeft(0x68, 0x53);
VibProbe vibRight(0x69, 0x1D);
const float VIB_MIN_RMS = 0.02f;   // g; di bawah ini dianggap motor diam
const float VIB_HYSTERESIS = 0.01f;  // g

bool i2cWrite(uint8_t addr, uint8_t reg, uint8_t val) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.write(val);
  return Wire.endTransmission() == 0;
}

bool i2cRead(uint8_t addr, uint8_t reg, uint8_t *buf, uint8_t len) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(addr, len) != len) return false;
  for (uint8_t i = 0; i < len; i++) buf[i] = Wire.read();
  return true;
}

void detectVib(VibProbe &p) {
  uint8_t id = 0;
  p.type = ACCEL_NONE;
  if (i2cRead(p.mpuAddr, 0x75, &id, 1) && (id == 0x68 || id == 0x70 || id == 0x71 || id == 0x73)) {
    i2cWrite(p.mpuAddr, 0x6B, 0x00);  // bangun dari sleep
    i2cWrite(p.mpuAddr, 0x1A, 0x01);  // DLPF 184 Hz
    i2cWrite(p.mpuAddr, 0x19, 0x00);  // sample rate 1 kHz
    i2cWrite(p.mpuAddr, 0x1C, 0x08);  // ±4 g
    p.type = ACCEL_MPU;
    p.addr = p.mpuAddr;
  } else if (i2cRead(p.adxlAddr, 0x00, &id, 1) && id == 0xE5) {
    i2cWrite(p.adxlAddr, 0x2C, 0x0D);  // 800 Hz
    i2cWrite(p.adxlAddr, 0x31, 0x09);  // full resolution, ±4 g
    i2cWrite(p.adxlAddr, 0x2D, 0x08);  // mulai mengukur
    p.type = ACCEL_ADXL;
    p.addr = p.adxlAddr;
  }
  p.failures = 0;
  p.primed = false;
  p.hz = p.type == ACCEL_NONE ? NAN : 0;
}

/// Baca percepatan (g) tiga sumbu.
bool readAccel(VibProbe &p, float g[3]) {
  uint8_t b[6];
  if (p.type == ACCEL_MPU) {
    if (!i2cRead(p.addr, 0x3B, b, 6)) return false;
    for (int i = 0; i < 3; i++) g[i] = (int16_t)(b[2 * i] << 8 | b[2 * i + 1]) / 8192.0f;
  } else {
    if (!i2cRead(p.addr, 0x32, b, 6)) return false;
    for (int i = 0; i < 3; i++) g[i] = (int16_t)(b[2 * i + 1] << 8 | b[2 * i]) * 0.0039f;
  }
  return true;
}

void sampleVib(VibProbe &p) {
  if (p.type == ACCEL_NONE) return;
  float g[3];
  if (!readAccel(p, g)) {
    if (++p.failures > 20) {  // sensor terlepas
      p.type = ACCEL_NONE;
      p.hz = NAN;
    }
    return;
  }
  p.failures = 0;
  for (int i = 0; i < 3; i++) {
    if (!p.primed) p.mean[i] = g[i];
    p.mean[i] += (g[i] - p.mean[i]) * 0.01f;
    float ac = g[i] - p.mean[i];
    p.energy[i] += ac * ac;
    if (!p.positive[i] && ac > VIB_HYSTERESIS) {
      p.positive[i] = true;
      p.crossings[i]++;
    } else if (p.positive[i] && ac < -VIB_HYSTERESIS) {
      p.positive[i] = false;
    }
  }
  p.primed = true;
  p.samples++;
}

void finishVibWindow(VibProbe &p, float seconds) {
  if (p.type == ACCEL_NONE || !p.samples) return;
  int axis = 0;
  for (int i = 1; i < 3; i++)
    if (p.energy[i] > p.energy[axis]) axis = i;
  float rms = sqrtf(p.energy[axis] / p.samples);
  p.hz = rms < VIB_MIN_RMS ? 0 : p.crossings[axis] / seconds;
  for (int i = 0; i < 3; i++) p.energy[i] = p.crossings[i] = 0;
  p.samples = 0;
}

void vibTask(void *) {
  Wire.begin(I2C_SDA, I2C_SCL, 400000);
  detectVib(vibLeft);
  detectVib(vibRight);
  unsigned long windowStart = millis(), lastDetect = millis();
  for (;;) {
    sampleVib(vibLeft);
    sampleVib(vibRight);
    unsigned long now = millis();
    if (now - windowStart >= 1000) {
      float sec = (now - windowStart) / 1000.0f;
      finishVibWindow(vibLeft, sec);
      finishVibWindow(vibRight, sec);
      windowStart = now;
    }
    if (now - lastDetect >= 10000) {
      lastDetect = now;
      if (vibLeft.type == ACCEL_NONE) detectVib(vibLeft);
      if (vibRight.type == ACCEL_NONE) detectVib(vibRight);
    }
    vTaskDelay(pdMS_TO_TICKS(2));
  }
}

/* ===== API ===== */
/// Ringkasan untuk status BLE, mis. "auto T2 V1" (jumlah sensor suhu & getar terdeteksi).
String summary() {
  char buf[24];
  snprintf(buf, sizeof(buf), "Sensor %s T%d V%d", MODE_NAMES[mode],
           tempLeft.present + tempRight.present,
           (vibLeft.type != ACCEL_NONE) + (vibRight.type != ACCEL_NONE));
  return buf;
}

bool setMode(const String &name) {
  for (uint8_t i = 0; i < 3; i++) {
    if (name == MODE_NAMES[i]) {
      mode = (Mode)i;
      prefs.putUChar("mode", i);
      return true;
    }
  }
  return false;
}

void begin() {
  prefs.begin("swavina", false);
  mode = (Mode)min<uint8_t>(prefs.getUChar("mode", MODE_AUTO), MODE_REAL);
  tempLeft.detect();
  tempRight.detect();
  lastTempDetect = lastTempPoll = millis();
  xTaskCreate(vibTask, "vib", 4096, nullptr, 2, nullptr);
}

/// Dipanggil saat terapi mulai / berhenti.
void setTarget(bool running, int temp, int vib) {
  active = running;
  if (running) {
    targetTemp = temp;
    targetVib = vib;
  }
}

/// Pilih nilai sensor atau simulasi sesuai mode.
float pick(float real, float sim, bool &usedSim) {
  if (mode == MODE_SIM || (mode == MODE_AUTO && isnan(real))) {
    usedSim = true;
    return sim;
  }
  return real;  // MODE_REAL: NAN bila sensor tidak ada
}

/// Panggil di loop(); memperbarui pembacaan tiap 200 ms.
void update() {
  unsigned long now = millis();
  if (now - lastUpdate < 200) return;
  float dt = lastUpdate ? (now - lastUpdate) / 1000.0f : 0.2f;
  lastUpdate = now;

  simulateFoot(simLeft, 45.0f, 0.0f, 0.99f, dt);
  simulateFoot(simRight, 60.0f, -0.4f, 0.97f, dt);

  if (now - lastTempPoll >= 1000) {
    lastTempPoll = now;
    tempLeft.poll();
    tempRight.poll();
  }
  if (now - lastTempDetect >= 10000) {
    lastTempDetect = now;
    if (!tempLeft.present) tempLeft.detect();
    if (!tempRight.present) tempRight.detect();
  }

  bool usedSim = false;
  leftFoot = {pick(tempLeft.value, simLeft.temp, usedSim), pick(vibLeft.hz, simLeft.vib, usedSim)};
  rightFoot = {pick(tempRight.value, simRight.temp, usedSim), pick(vibRight.hz, simRight.vib, usedSim)};
  anySimulated = usedSim;
}

}  // namespace sensors
