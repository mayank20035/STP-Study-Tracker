import 'package:flutter/material.dart';

import '../logic/day_utils.dart';
import '../models/models.dart';

class BackupFormatException implements Exception {
  final String message;
  BackupFormatException(this.message);
  @override
  String toString() => message;
}

enum BackupKind { v2, v1 }

BackupKind detectBackup(Map<String, dynamic> j) {
  if (j['app'] == 'STP' && (j['schema'] as num?) == 2) return BackupKind.v2;
  if (j['subjects'] is List && (j['logs'] is Map || j['categories'] is List)) return BackupKind.v1;
  throw BackupFormatException('This file is not an STP backup.');
}

AppData decodeBackup(Map<String, dynamic> j) {
  switch (detectBackup(j)) {
    case BackupKind.v2:
      final data = AppData.fromJson(j);
      // Never import a running timer from another device.
      data.activeTimer = null;
      data.pomodoro = null;
      return data;
    case BackupKind.v1:
      return convertV1Backup(j);
  }
}

/// Converts a v1 (React Native) `STP_Backup.json` into v2 data.
///
/// v1 only stored per-chapter daily totals, so each day becomes one
/// "imported" session placed at 9 AM of that study day. Any chapter time
/// that is not covered by daily history is kept as legacy time so all-time
/// totals still match v1 exactly.
AppData convertV1Backup(Map<String, dynamic> j, {int dayStartHour = 5}) {
  final subjects = <Subject>[];
  final sessions = <StudySession>[];
  final exportedAt = DateTime.tryParse(j['timestamp']?.toString() ?? '')?.millisecondsSinceEpoch;

  final rawSubjects = (j['subjects'] as List?) ?? [];
  for (var i = 0; i < rawSubjects.length; i++) {
    final rs = Map<String, dynamic>.from(rawSubjects[i] as Map);
    final sid = 'v1s_${rs['id']}';
    final badges = rs['badges'] is Map ? Map<String, dynamic>.from(rs['badges'] as Map) : null;
    final subject = Subject(
      id: sid,
      name: (rs['name'] ?? 'Subject').toString(),
      emoji: subjectEmojis[i % subjectEmojis.length],
      color: subjectPalette[i % subjectPalette.length],
      targetHours: ((rs['target'] as num?)?.toDouble() ?? 100).clamp(1, 100000).toDouble(),
      category: (rs['category'] ?? '').toString(),
      note: (rs['note'] ?? '').toString(),
      legacyMedals: Medals.fromJson(badges),
    );

    final rawChapters = (rs['chapters'] as List?) ?? [];
    for (final rcAny in rawChapters) {
      final rc = Map<String, dynamic>.from(rcAny as Map);
      final cid = 'v1c_${rc['id']}';
      final chapter = Chapter(
        id: cid,
        name: (rc['name'] ?? 'Chapter').toString(),
        hidden: rc['isHidden'] == true,
      );
      final history = rc['dailyHistory'] is Map
          ? Map<String, dynamic>.from(rc['dailyHistory'] as Map)
          : <String, dynamic>{};
      var covered = 0;
      final keys = history.keys.toList()..sort();
      for (final key in keys) {
        final ms = (history[key] as num?)?.toInt() ?? 0;
        if (ms <= 0 || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key)) continue;
        final dur = ms.clamp(0, 20 * 3600000);
        final dayStart = dayStartMoment(key, dayStartHour);
        // 9 AM by default, earlier when the day is very long so it never
        // spills into the next study day.
        final offset = (20 * 3600000 - dur).clamp(0, 4 * 3600000);
        final start = dayStart.millisecondsSinceEpoch + offset;
        sessions.add(StudySession(
          id: 'v1_${cid}_$key',
          subjectId: sid,
          chapterId: cid,
          startMs: start,
          endMs: start + dur,
          manual: true,
        ));
        covered += ms;
      }
      final timeSpent = (rc['timeSpent'] as num?)?.toInt() ?? 0;
      final remainder = timeSpent - covered;
      if (remainder > 60000) chapter.legacyMs = remainder;

      // A timer that was running when v1 exported.
      final last = (rc['lastStartTime'] as num?)?.toInt();
      if (rc['isRunning'] == true && last != null && exportedAt != null && exportedAt > last) {
        final end = exportedAt.clamp(last, last + 12 * 3600000);
        sessions.add(StudySession(
            id: 'v1run_$cid', subjectId: sid, chapterId: cid, startMs: last, endMs: end));
      }
      subject.chapters.add(chapter);
    }
    subjects.add(subject);
  }

  final goals = ((j['goals'] as List?) ?? [])
      .map((g) => LevelGoal.fromJson(Map<String, dynamic>.from(g as Map)))
      .toList();
  final categories = ((j['categories'] as List?) ?? []).map((e) => e.toString()).toList();
  final settings = AppSettings(
    themeMode: j['isDarkMode'] == true ? ThemeMode.dark : ThemeMode.light,
    dayStartHour: dayStartHour,
  );
  if (goals.isNotEmpty) {
    final active = j['activeGoalId']?.toString();
    settings.activeGoalId = goals.any((g) => g.id == active) ? active! : goals.first.id;
  }

  sessions.sort((a, b) => a.startMs.compareTo(b.startMs));
  return AppData(
    subjects: subjects,
    sessions: sessions,
    goals: goals.isEmpty ? null : goals,
    categories: categories.isEmpty ? null : categories,
    settings: settings,
  );
}
