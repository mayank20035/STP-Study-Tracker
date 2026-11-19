import 'package:flutter_test/flutter_test.dart';
import 'package:stp_v2/logic/day_utils.dart';
import 'package:stp_v2/logic/stats.dart';
import 'package:stp_v2/models/models.dart';
import 'package:stp_v2/services/backup_codec.dart';

int ms(DateTime d) => d.millisecondsSinceEpoch;

void main() {
  group('day boundary', () {
    test('1 AM belongs to the previous study day (5 AM reset)', () {
      expect(dayKeyFor(DateTime(2026, 3, 10, 1, 30), 5), '2026-03-09');
      expect(dayKeyFor(DateTime(2026, 3, 10, 5, 0), 5), '2026-03-10');
      expect(dayKeyFor(DateTime(2026, 3, 1, 2), 5), '2026-02-28');
    });

    test('session crossing 5 AM is split between both days', () {
      final split = splitByDay(ms(DateTime(2026, 3, 10, 4)), ms(DateTime(2026, 3, 10, 6)), 5);
      expect(split['2026-03-09'], 3600000);
      expect(split['2026-03-10'], 3600000);
    });

    test('formatting', () {
      expect(formatClock(3723000), '01:02:03');
      expect(formatDuration(5400000), '1h 30m');
      expect(formatDuration(0), '0m');
    });
  });

  group('streaks', () {
    test('current streak continues from yesterday if today is empty', () {
      final daily = {
        '2026-03-07': 3600000,
        '2026-03-08': 3600000,
        '2026-03-09': 3600000,
      };
      final s = computeStreak(daily, '2026-03-10', 60000);
      expect(s.current, 3);
      expect(s.todayDone, false);
    });

    test('longest streak across gaps', () {
      final daily = {
        '2026-01-01': 1, '2026-01-02': 1, '2026-01-03': 1, '2026-01-04': 1,
        '2026-01-10': 1, '2026-01-11': 1,
      };
      final s = computeStreak(daily, '2026-01-11', 1);
      expect(s.current, 2);
      expect(s.longest, 4);
    });

    test('days below the minimum do not count', () {
      final s = computeStreak({'2026-01-01': 60000}, '2026-01-01', 15 * 60000);
      expect(s.current, 0);
    });
  });

  group('stats snapshot', () {
    test('daily medals use each day\'s time, not all-time totals', () {
      final a = Subject(id: 'a', name: 'A');
      final b = Subject(id: 'b', name: 'B');
      final sessions = [
        // Day 1: A wins.
        StudySession(id: '1', subjectId: 'a', startMs: ms(DateTime(2026, 1, 1, 9)), endMs: ms(DateTime(2026, 1, 1, 15))),
        StudySession(id: '2', subjectId: 'b', startMs: ms(DateTime(2026, 1, 1, 16)), endMs: ms(DateTime(2026, 1, 1, 17))),
        // Day 2: B wins even though A has more all-time hours.
        StudySession(id: '3', subjectId: 'a', startMs: ms(DateTime(2026, 1, 2, 9)), endMs: ms(DateTime(2026, 1, 2, 10))),
        StudySession(id: '4', subjectId: 'b', startMs: ms(DateTime(2026, 1, 2, 11)), endMs: ms(DateTime(2026, 1, 2, 14))),
      ];
      final snap = StatsSnapshot.compute(
          subjects: [a, b], sessions: sessions, dayStartHour: 5, todayKey: '2026-01-05');
      expect(snap.medals['a']!.gold, 1);
      expect(snap.medals['b']!.gold, 1);
      expect(snap.medals['a']!.silver, 1);
      expect(snap.totalMs, 11 * 3600000);
      expect(snap.daily['2026-01-02'], 4 * 3600000);
    });

    test('xp levels', () {
      expect(levelForXp(0), 1);
      expect(levelForXp(100), 2);
      expect(levelForXp(99), 1);
      expect(titleForLevel(12), 'Scholar');
    });
  });

  group('v1 backup import', () {
    final v1 = {
      'subjects': [
        {
          'id': 1700000000000,
          'name': 'Physics',
          'hours': 5.5,
          'target': 200,
          'progress': 0.0275,
          'badges': {'gold': 3, 'silver': 1, 'bronze': 0},
          'note': 'Mechanics first',
          'category': 'Exam Prep',
          'chapters': [
            {
              'id': '111',
              'name': 'Kinematics',
              'timeSpent': 5 * 3600000,
              'dailyHistory': {'2025-12-01': 2 * 3600000, '2025-12-02': 1 * 3600000},
              'isRunning': false,
              'lastStartTime': null,
              'isHidden': true,
            },
            {
              'id': '112',
              'name': 'Optics',
              'timeSpent': 30 * 60000,
              'dailyHistory': {},
              'isRunning': false,
              'lastStartTime': null,
            },
          ],
        },
      ],
      'logs': {'2025-12-01': 2 * 3600000, '2025-12-02': 3600000},
      'goals': [
        {'id': '1', 'label': 'Beginner', 'hours': 1000},
        {'id': '9', 'label': 'Custom', 'hours': 300},
      ],
      'categories': ['Exam Prep', 'Workout'],
      'activeGoalId': '9',
      'isDarkMode': true,
      'timestamp': '2025-12-03T10:00:00.000Z',
      'version': '1.1.0',
    };

    test('is detected and converted without losing time', () {
      expect(detectBackup(v1), BackupKind.v1);
      final data = decodeBackup(v1);
      expect(data.subjects, hasLength(1));
      final s = data.subjects.first;
      expect(s.name, 'Physics');
      expect(s.targetHours, 200);
      expect(s.note, 'Mechanics first');
      expect(s.category, 'Exam Prep');
      expect(s.legacyMedals.gold, 3);
      expect(s.chapters.first.hidden, true);
      expect(data.sessions, hasLength(2));
      expect(data.settings.activeGoalId, '9');

      final snap = StatsSnapshot.compute(
          subjects: data.subjects, sessions: data.sessions, dayStartHour: 5, todayKey: '2026-01-01');
      // 5h Kinematics + 0.5h Optics = 5.5h, exactly like v1.
      expect(snap.totalMs, 5 * 3600000 + 30 * 60000);
      expect(snap.daily['2025-12-01'], 2 * 3600000);
      expect(snap.daily['2025-12-02'], 3600000);
    });

    test('v2 backups round-trip', () {
      final data = decodeBackup(v1);
      final again = decodeBackup(data.toJson());
      expect(again.subjects.first.chapters.length, 2);
      expect(again.sessions.length, data.sessions.length);
    });

    test('random json is rejected', () {
      expect(() => detectBackup({'hello': 'world'}), throwsA(isA<BackupFormatException>()));
    });
  });
}
