import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/clinical.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/swavina_scaffold.dart';

final _isoDate = DateFormat('yyyy-MM-dd');

/// Satu data ukur (nilai + waktu terakhir diukur).
class _Measure {
  _Measure({DateTime? date}) : date = date ?? DateTime.now();
  final TextEditingController controller = TextEditingController();
  DateTime date;
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isEditing = false;

  final _name = TextEditingController();
  DateTime _birthDate = DateTime(1990, 6, 12);
  final _height = _Measure();
  final _weight = _Measure();
  final _bloodSugar = _Measure();
  final _bloodPressure = _Measure();
  String? _profileImage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    for (final m in [_height, _weight, _bloodSugar, _bloodPressure]) {
      m.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = Map<String, dynamic>.from(await Api.get('/profile') as Map);
      if (!mounted) return;
      DateTime? d(String k) => p[k] is String ? DateTime.tryParse(p[k] as String) : null;
      String? s(String k) => p[k] == null ? null : '${p[k]}';
      setState(() {
        if (s('name') != null) _name.text = s('name')!;
        _birthDate = d('birth_date') ?? _birthDate;
        if (s('height') != null) _height.controller.text = s('height')!;
        _height.date = d('height_date') ?? _height.date;
        if (s('weight') != null) _weight.controller.text = s('weight')!;
        _weight.date = d('weight_date') ?? _weight.date;
        if (s('blood_sugar') != null) _bloodSugar.controller.text = s('blood_sugar')!;
        _bloodSugar.date = d('blood_sugar_date') ?? _bloodSugar.date;
        if (s('blood_pressure') != null) _bloodPressure.controller.text = s('blood_pressure')!;
        _bloodPressure.date = d('blood_pressure_date') ?? _bloodPressure.date;
        if (s('profile_image') != null) _profileImage = s('profile_image');
      });
    } catch (_) {}
  }

  int get _age {
    final now = DateTime.now();
    var age = now.year - _birthDate.year;
    final m = now.month - _birthDate.month;
    if (m < 0 || (m == 0 && now.day < _birthDate.day)) age--;
    return age;
  }

  Future<void> _save() async {
    try {
      await Api.put('/profile', {
        'name': _name.text,
        'birth_date': _isoDate.format(_birthDate),
        'height': double.tryParse(_height.controller.text) ?? 0,
        'height_date': _isoDate.format(_height.date),
        'weight': double.tryParse(_weight.controller.text) ?? 0,
        'weight_date': _isoDate.format(_weight.date),
        'blood_sugar': _bloodSugar.controller.text,
        'blood_sugar_date': _isoDate.format(_bloodSugar.date),
        'blood_pressure': _bloodPressure.controller.text,
        'blood_pressure_date': _isoDate.format(_bloodPressure.date),
        'profile_image': _profileImage,
      });
      if (mounted) setState(() => _isEditing = false);
    } on ApiException catch (e) {
      if (mounted) await showAlert(context, 'Error', e.message);
    }
  }

  Future<void> _cancel() async {
    setState(() => _isEditing = false);
    await _load(); // kembalikan nilai dari server
  }

  Future<void> _pickPhoto(ImageSource source) async {
    Navigator.pop(context);
    try {
      final x = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1024);
      if (x != null && mounted) setState(() => _profileImage = x.path);
    } catch (_) {
      if (mounted) await showAlert(context, 'Izin Ditolak', 'Izinkan akses kamera/galeri di pengaturan.');
    }
  }

  void _openPhotoSheet() {
    final c = AppColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ubah Foto Profil',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.textPrimary)),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.camera_alt_outlined, color: c.textPrimary),
              title: Text('Ambil dari Kamera',
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.textPrimary)),
              onTap: () => _pickPhoto(ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.image_outlined, color: c.textPrimary),
              title: Text('Pilih dari Galeri',
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.textPrimary)),
              onTap: () => _pickPhoto(ImageSource.gallery),
            ),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal',
                    style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await Api.clearSession();
    await ClinicalData.clearCache();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  ImageProvider _avatar() {
    final img = _profileImage;
    if (img != null && img.isNotEmpty) {
      if (img.startsWith('http')) return NetworkImage(img);
      final f = File(img.replaceFirst('file://', ''));
      if (f.existsSync()) return FileImage(f);
    }
    return const AssetImage('assets/images/logo_swavina.png');
  }

  Future<void> _pickBirth() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _birthDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _birthDate = d);
  }

  Future<void> _pickMeasureDate(_Measure m) async {
    final d = await showDatePicker(
      context: context,
      initialDate: m.date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(m.date));
    setState(() {
      m.date = DateTime(d.year, d.month, d.day, t?.hour ?? m.date.hour, t?.minute ?? m.date.minute);
    });
  }

  Widget _section(AppColors c, String title) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(title,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.textPrimary)),
      );

  Widget _measureCard(AppColors c, String title, _Measure m, String unit) {
    final editable = _isEditing;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: editable ? c.card : c.cardAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: editable ? AppColors.accent : c.border,
          width: editable ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
              if (!editable) Icon(Icons.lock_outline, size: 16, color: c.textSecondary),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: m.controller,
                  enabled: editable,
                  keyboardType: TextInputType.number,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.textPrimary),
                  decoration: const InputDecoration.collapsed(hintText: '-'),
                ),
              ),
              const SizedBox(width: 8),
              Text(unit, style: TextStyle(fontSize: 16, color: c.textSecondary)),
            ],
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: editable ? () => _pickMeasureDate(m) : null,
            child: Text(
              'Terakhir diukur: ${DateFormat('d MMM yyyy HH:mm').format(m.date)}',
              style: TextStyle(color: editable ? AppColors.accent : c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return SwavinaScaffold(
      onRefresh: _isEditing ? null : _load,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Profile',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c.textPrimary)),
                if (!_isEditing)
                  IconButton(
                    onPressed: () => setState(() => _isEditing = true),
                    icon: Icon(Icons.edit_outlined, color: c.textPrimary),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // AVATAR
            Center(
              child: Column(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(radius: 55, backgroundColor: c.cardAlt, backgroundImage: _avatar()),
                      if (_isEditing)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _openPhotoSheet,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(_name.text,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.textPrimary)),
                  Text('$_age tahun', style: TextStyle(color: c.textSecondary)),
                ],
              ),
            ),

            _section(c, 'Informasi Pribadi'),
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: _isEditing ? c.card : c.cardAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border),
              ),
              child: TextField(
                controller: _name,
                enabled: _isEditing,
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: 16, color: c.textPrimary),
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Nama'),
              ),
            ),
            Material(
              color: _isEditing ? c.card : c.cardAlt,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _isEditing ? _pickBirth : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.border),
                  ),
                  child: Text('Tanggal Lahir: ${DateFormat('d MMM yyyy').format(_birthDate)}',
                      style: TextStyle(fontSize: 16, color: c.textPrimary)),
                ),
              ),
            ),

            _section(c, 'Data Tubuh'),
            _measureCard(c, 'Tinggi Badan', _height, 'cm'),
            _measureCard(c, 'Berat Badan', _weight, 'kg'),

            _section(c, 'Data Kesehatan'),
            _measureCard(c, 'Gula Darah', _bloodSugar, 'mg/dL'),
            _measureCard(c, 'Tekanan Darah', _bloodPressure, 'mmHg'),

            if (_isEditing) ...[
              const SizedBox(height: 14),
              PrimaryButton(label: 'Simpan Perubahan', onPressed: _save, radius: 18, fontSize: 18),
              Center(
                child: TextButton(
                  onPressed: _cancel,
                  child: Text('Batal', style: TextStyle(fontSize: 16, color: c.textSecondary)),
                ),
              ),
            ],
            const SizedBox(height: 25),
            PrimaryButton(
              label: 'Logout',
              onPressed: _logout,
              color: AppColors.deleteRed,
              radius: 14,
              fontSize: 16,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ],
        ),
      ),
    );
  }
}
