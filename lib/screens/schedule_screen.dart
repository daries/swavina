import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/swavina_scaffold.dart';

final _dateFmt = DateFormat('yyyy-MM-dd');
final _timeFmt = DateFormat('HH:mm:ss');

class ScheduleValues {
  const ScheduleValues({
    required this.date,
    required this.duration,
    required this.temperature,
    required this.vibration,
  });

  final DateTime date;
  final int duration;
  final int temperature;
  final int vibration;

  Map<String, dynamic> toBody() => {
        'date': _dateFmt.format(date),
        'time': _timeFmt.format(date),
        'duration': duration,
        'temperature': temperature,
        'vibration': vibration,
      };
}

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  List<Map<String, dynamic>> _schedules = [];
  bool _loading = true;
  int _formKey = 0; // untuk mereset form setelah simpan

  @override
  void initState() {
    super.initState();
    _fetch();
    AppState.tabIndex.addListener(_onTab);
  }

  @override
  void dispose() {
    AppState.tabIndex.removeListener(_onTab);
    super.dispose();
  }

  void _onTab() {
    if (AppState.tabIndex.value == AppState.tabSchedule) _fetch();
  }

  Future<void> _fetch() async {
    try {
      final data = await Api.get('/schedule');
      final list = (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) setState(() => _schedules = list);
    } on ApiException catch (e) {
      if (mounted) await showAlert(context, 'Error', e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _save(ScheduleValues v) async {
    try {
      await Api.post('/schedule', v.toBody());
      await _fetch();
      if (mounted) setState(() => _formKey++);
      return true;
    } on ApiException catch (e) {
      if (mounted) await showAlert(context, 'Error', e.message);
      return false;
    }
  }

  Future<void> _delete(int id) async {
    if (!await confirmDelete(context, 'Hapus jadwal ini?')) return;
    try {
      await Api.delete('/schedule/$id');
      if (mounted) setState(() => _schedules.removeWhere((s) => s['id'] == id));
    } on ApiException catch (e) {
      if (mounted) await showAlert(context, 'Error', e.message);
    }
  }

  DateTime _parse(Map<String, dynamic> item) {
    return DateTime.tryParse('${item['date']} ${item['time']}') ?? DateTime.now();
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    final id = (item['id'] as num).toInt();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final c = AppColors.of(ctx);
        return Dialog(
          backgroundColor: c.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edit Schedule',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.textPrimary)),
                const SizedBox(height: 10),
                ScheduleEditor(
                  initialDate: _parse(item),
                  initialDuration: (item['duration'] as num?)?.toInt(),
                  initialTemperature: (item['temperature'] as num?)?.toInt() ?? 38,
                  initialVibration: (item['vibration'] as num?)?.toInt() ?? 45,
                  submitLabel: 'Update',
                  onSubmit: (v) async {
                    try {
                      await Api.put('/schedule/$id', v.toBody());
                      await _fetch();
                      if (ctx.mounted) Navigator.pop(ctx);
                      return true;
                    } on ApiException catch (e) {
                      if (ctx.mounted) await showAlert(ctx, 'Error', e.message);
                      return false;
                    }
                  },
                ),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Batal', style: TextStyle(color: c.textSecondary)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return SwavinaScaffold(
      onRefresh: _fetch,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Therapy Schedule',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c.textPrimary)),
                  const SizedBox(height: 20),
                  ScheduleEditor(
                    key: ValueKey(_formKey),
                    submitLabel: 'Save Schedule',
                    onSubmit: _save,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('Schedule List',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.textPrimary)),
            ),
            if (_loading) const Center(child: CircularProgressIndicator(color: AppColors.accent)),
            for (final item in _schedules)
              CardBox(
                radius: 18,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${item['date']} • ${item['time']}',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '${item['duration']} min | ${item['temperature']}°C | ${item['vibration']} Hz',
                        style: TextStyle(fontSize: 14, color: c.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      children: [
                        _smallBtn('Edit', AppColors.warning, () => _edit(item)),
                        _smallBtn('Delete', AppColors.deleteRed, () => _delete((item['id'] as num).toInt())),
                        _smallBtn('Start', AppColors.success, () {
                          AppState.startTherapyFromSchedule(TherapyRequest(
                            duration: (item['duration'] as num).toInt(),
                            temperature: (item['temperature'] as num).toInt(),
                            vibration: (item['vibration'] as num).toInt(),
                            fromSchedule: true,
                          ));
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _smallBtn(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

/// Form jadwal (tanggal, jam, durasi, suhu, getaran) — dipakai untuk
/// membuat jadwal baru dan mengedit jadwal.
class ScheduleEditor extends StatefulWidget {
  const ScheduleEditor({
    super.key,
    this.initialDate,
    this.initialDuration,
    this.initialTemperature = 38,
    this.initialVibration = 45,
    required this.submitLabel,
    required this.onSubmit,
  });

  final DateTime? initialDate;
  final int? initialDuration;
  final int initialTemperature;
  final int initialVibration;
  final String submitLabel;
  final Future<bool> Function(ScheduleValues values) onSubmit;

  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  late DateTime _date = widget.initialDate ?? DateTime.now();
  late int _temperature = widget.initialTemperature.clamp(minTemperature, maxTemperature);
  late int _vibration = widget.initialVibration;
  late final TextEditingController _duration =
      TextEditingController(text: widget.initialDuration?.toString() ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _duration.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (t != null) {
      setState(() => _date = DateTime(_date.year, _date.month, _date.day, t.hour, t.minute));
    }
  }

  Future<void> _submit() async {
    final duration = int.tryParse(_duration.text.trim());
    if (duration == null || duration <= 0) {
      await showAlert(context, 'Error', 'Durasi wajib diisi');
      return;
    }
    setState(() => _saving = true);
    final ok = await widget.onSubmit(ScheduleValues(
      date: _date,
      duration: duration,
      temperature: _temperature,
      vibration: _vibration,
    ));
    if (mounted) {
      setState(() {
        _saving = false;
        if (ok && widget.initialDate == null) _duration.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    Widget box(Widget child, {VoidCallback? onTap}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: c.cardAlt,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(14), child: child),
          ),
        ),
      );
    }

    Widget sliderCard(String label, int value, double min, double max, Color color,
        ValueChanged<int> onChanged) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.cardAlt, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
            Slider(
              min: min,
              max: max,
              divisions: (max - min).round(),
              value: value.toDouble(),
              activeColor: color,
              inactiveColor: c.sliderTrack,
              onChanged: (v) => onChanged(v.round()),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        box(
          Text('Date: ${DateFormat('d MMM yyyy').format(_date)}',
              style: TextStyle(color: c.textPrimary)),
          onTap: _pickDate,
        ),
        box(
          Text('Time: ${DateFormat('HH:mm').format(_date)}',
              style: TextStyle(color: c.textPrimary)),
          onTap: _pickTime,
        ),
        box(
          TextField(
            controller: _duration,
            keyboardType: TextInputType.number,
            style: TextStyle(fontSize: 16, color: c.textPrimary),
            decoration: InputDecoration.collapsed(
              hintText: 'Duration (minutes)',
              hintStyle: TextStyle(color: c.textSecondary),
            ),
          ),
        ),
        sliderCard('Temperature: $_temperature°C', _temperature, minTemperature.toDouble(), maxTemperature.toDouble(), AppColors.accent,
            (v) => setState(() => _temperature = v)),
        sliderCard('Vibration: $_vibration Hz', _vibration, 30, 60, AppColors.vibration,
            (v) => setState(() => _vibration = v)),
        const SizedBox(height: 4),
        PrimaryButton(
          label: _saving ? 'Menyimpan...' : widget.submitLabel,
          onPressed: _saving ? null : _submit,
          fontSize: 18,
        ),
      ],
    );
  }
}
