import 'package:flutter/foundation.dart';

/// Batas suhu terapi (°C). Maksimal 40 °C demi keamanan kulit pasien DM.
const int minTemperature = 30;
const int maxTemperature = 40;

/// Parameter terapi yang dikirim dari jadwal ke tab Therapy.
class TherapyRequest {
  const TherapyRequest({
    required this.duration,
    required this.temperature,
    required this.vibration,
    this.fromSchedule = false,
  });

  final int duration;
  final int temperature;
  final int vibration;
  final bool fromSchedule;
}

/// State global ringan untuk navigasi antar tab (pengganti params expo-router).
class AppState {
  AppState._();

  static const int tabHome = 0;
  static const int tabTherapy = 1;
  static const int tabSchedule = 2;
  static const int tabHistory = 3;
  static const int tabProfile = 4;

  static final ValueNotifier<int> tabIndex = ValueNotifier<int>(tabHome);
  static final ValueNotifier<TherapyRequest?> therapyRequest =
      ValueNotifier<TherapyRequest?>(null);

  /// Buka tab Therapy dengan parameter dari jadwal.
  static void startTherapyFromSchedule(TherapyRequest req) {
    therapyRequest.value = req;
    tabIndex.value = tabTherapy;
  }
}
