import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Database SQLite lokal (offline) untuk riwayat terapi.
class LocalDb {
  LocalDb._();

  static Database? _db;

  static Future<Database> _open() async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'swavina.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS therapy_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT,
            start_time TEXT,
            duration INTEGER,
            temperature INTEGER,
            vibration INTEGER
          )
        ''');
      },
    );
    return _db!;
  }

  static Future<void> insertTherapy({
    required String date,
    required String startTime,
    required int duration,
    required int temperature,
    required int vibration,
  }) async {
    final db = await _open();
    await db.insert('therapy_history', {
      'date': date,
      'start_time': startTime,
      'duration': duration,
      'temperature': temperature,
      'vibration': vibration,
    });
  }
}
