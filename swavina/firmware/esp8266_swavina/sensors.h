#pragma once
#include <Arduino.h>

// Sensor kaki kiri & kanan: suhu (°C) dan getaran (Hz).
//
// SIMULATE_SENSORS 1 → nilai disimulasikan (belum ada hardware sensor):
//  - suhu naik bertahap dari suhu kulit menuju target saat terapi berjalan
//    (respon orde-1, kaki kanan sedikit lebih lambat & lebih dingin), lalu
//    turun lagi saat terapi berhenti;
//  - getaran mengikuti setting ±noise, kembali ke 0 saat berhenti.
// Ganti ke 0 dan isi readFootTemp()/readFootVib() untuk sensor sungguhan
// (mis. DS18B20 / NTC untuk suhu, akselerometer / piezo untuk getaran).
#define SIMULATE_SENSORS 1

struct FootReading {
  float temp;  // °C
  float vib;   // Hz
};

FootReading leftFoot = {31.5f, 0};
FootReading rightFoot = {31.2f, 0};

namespace sensors {

bool active = false;
float targetTemp = 0;
float targetVib = 0;
unsigned long lastUpdate = 0;

#if SIMULATE_SENSORS
const float SKIN_TEMP = 31.5f;  // suhu kulit kaki saat istirahat

float noise(float amp) { return amp * (random(-1000, 1001) / 1000.0f); }

void simulateFoot(FootReading &f, float tauSec, float tempOffset, float vibFactor, float dt) {
  float goalTemp = active ? targetTemp + tempOffset : SKIN_TEMP + tempOffset;
  f.temp += (goalTemp - f.temp) * min(1.0f, dt / tauSec) + noise(0.04f);

  float goalVib = active ? targetVib * vibFactor : 0;
  f.vib += (goalVib - f.vib) * min(1.0f, dt / 0.8f);  // motor butuh ±1 detik
  if (active) f.vib += noise(0.6f);
  if (f.vib < 0.05f) f.vib = 0;
}
#else
float readFootTemp(bool left) { return NAN; }  // TODO: baca sensor suhu
float readFootVib(bool left) { return NAN; }   // TODO: baca sensor getaran
#endif

/// Dipanggil saat terapi mulai / berhenti.
void setTarget(bool running, int temp, int vib) {
  active = running;
  if (running) {
    targetTemp = temp;
    targetVib = vib;
  }
}

/// Panggil di loop(); memperbarui pembacaan tiap 200 ms.
void update() {
  unsigned long now = millis();
  if (now - lastUpdate < 200) return;
  float dt = lastUpdate ? (now - lastUpdate) / 1000.0f : 0.2f;
  lastUpdate = now;
#if SIMULATE_SENSORS
  simulateFoot(leftFoot, 45.0f, 0.0f, 0.99f, dt);
  simulateFoot(rightFoot, 60.0f, -0.4f, 0.97f, dt);
#else
  leftFoot = {readFootTemp(true), readFootVib(true)};
  rightFoot = {readFootTemp(false), readFootVib(false)};
#endif
}

}  // namespace sensors
