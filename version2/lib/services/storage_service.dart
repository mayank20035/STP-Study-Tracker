import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'backup_codec.dart';

class StorageService {
  static const _key = 'stp_v2_data';

  Future<AppData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return AppData();
    try {
      return AppData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Keep a copy of unreadable data instead of silently losing it.
      await prefs.setString('${_key}_corrupt_${DateTime.now().millisecondsSinceEpoch}', raw);
      return AppData();
    }
  }

  Future<void> save(AppData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data.toJson()));
  }

  Future<void> exportBackup(AppData data) async {
    final dir = await getTemporaryDirectory();
    final name = 'STP_v2_Backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json';
    final file = File('${dir.path}/$name');
    await file.writeAsString(const JsonEncoder.withIndent(' ').convert(data.toJson()));
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: 'STP Backup',
      title: 'Save STP Backup',
    ));
  }

  /// Returns null when the user cancels.
  Future<AppData?> pickBackup() async {
    final file = await FilePicker.pickFile(type: FileType.any, dialogTitle: 'Choose STP backup');
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw BackupFormatException('Could not read the file. Is it a .json backup?');
    }
    if (decoded is! Map) throw BackupFormatException('This file is not an STP backup.');
    return decodeBackup(Map<String, dynamic>.from(decoded));
  }
}
