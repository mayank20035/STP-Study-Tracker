import '../models/models.dart';
import 'day_utils.dart';

/// Aggregates derived from all completed sessions. Recomputed only when the
/// data changes; the live (running) timer is layered on top by the store.
class StatsSnapshot {
  final Map<String, int> daily = {};
  final Map<String, Map<String, int>> subjectDaily = {};

  /// Time per subject per To-Do book page: a session counts toward its
  /// [StudySession.planDay] when set, otherwise toward the day it was studied.
  final Map<String, Map<String, int>> planDaily = {};
  final Map<String, int> subjectTotal = {};
  final Map<String, int> chapterTotal = {};
  final Map<String, int> subjectSessionMs = {};
  final List<int> hourBuckets = List.filled(24, 0);
  final Map<String, Medals> medals = {};
  int totalMs = 0;
  int sessionCount = 0;
  int longestSessionMs = 0;
  bool hasNightSession = false;
  bool hasEarlySession = false;

  StatsSnapshot.compute({
    required List<Subject> subjects,
    required List<StudySession> sessions,
    required int dayStartHour,
    required String todayKey,
  }) {
    for (final s in subjects) {
      subjectTotal[s.id] = s.legacyMs + s.chapters.fold<int>(0, (a, c) => a + c.legacyMs);
      for (final c in s.chapters) {
        chapterTotal[c.id] = c.legacyMs;
      }
      totalMs += subjectTotal[s.id]!;
    }
    for (final ses in sessions) {
      final d = ses.durationMs;
      if (d <= 0) continue;
      sessionCount++;
      if (d > longestSessionMs) longestSessionMs = d;
      totalMs += d;
      subjectTotal[ses.subjectId] = (subjectTotal[ses.subjectId] ?? 0) + d;
      subjectSessionMs[ses.subjectId] = (subjectSessionMs[ses.subjectId] ?? 0) + d;
      if (ses.chapterId != null) {
        chapterTotal[ses.chapterId!] = (chapterTotal[ses.chapterId!] ?? 0) + d;
      }
      final perDay = splitByDay(ses.startMs, ses.endMs, dayStartHour);
      final sd = subjectDaily.putIfAbsent(ses.subjectId, () => {});
      perDay.forEach((k, v) {
        daily[k] = (daily[k] ?? 0) + v;
        sd[k] = (sd[k] ?? 0) + v;
      });
      final pd = planDaily.putIfAbsent(ses.subjectId, () => {});
      if (ses.planDay != null) {
        pd[ses.planDay!] = (pd[ses.planDay!] ?? 0) + d;
      } else {
        perDay.forEach((k, v) => pd[k] = (pd[k] ?? 0) + v);
      }
      if (!ses.manual) {
        final hb = List.filled(24, 0);
        addToHourBuckets(hb, ses.startMs, ses.endMs);
        for (var h = 0; h < 24; h++) {
          hourBuckets[h] += hb[h];
        }
        // Night owl: 10+ minutes studied between midnight and 4 AM.
        if (hb[0] + hb[1] + hb[2] + hb[3] >= 600000) hasNightSession = true;
        // Early bird: a session started between 5 and 7 AM.
        final sh = ses.start.hour;
        if (sh >= 5 && sh < 7) hasEarlySession = true;
      }
    }

    // Daily medals: for every finished day, the top 3 subjects of that day
    // win gold / silver / bronze (v1 wrongly used all-time totals).
    final perDayRank = <String, List<MapEntry<String, int>>>{};
    subjectDaily.forEach((sid, days) {
      days.forEach((k, v) {
        if (k.compareTo(todayKey) >= 0 || v <= 0) return;
        perDayRank.putIfAbsent(k, () => []).add(MapEntry(sid, v));
      });
    });
    for (final s in subjects) {
      medals[s.id] = s.legacyMedals;
    }
    perDayRank.forEach((_, list) {
      list.sort((a, b) => b.value.compareTo(a.value));
      for (var i = 0; i < list.length && i < 3; i++) {
        final cur = medals[list[i].key] ?? const Medals();
        medals[list[i].key] = cur +
            Medals(gold: i == 0 ? 1 : 0, silver: i == 1 ? 1 : 0, bronze: i == 2 ? 1 : 0);
      }
    });
  }
}

class StreakInfo {
  final int current;
  final int longest;
  final bool todayDone;
  const StreakInfo(this.current, this.longest, this.todayDone);
}

StreakInfo computeStreak(Map<String, int> daily, String todayKey, int minMs) {
  bool ok(String k) => (daily[k] ?? 0) >= minMs && (daily[k] ?? 0) > 0;
  final todayDone = ok(todayKey);
  var current = 0;
  var cursor = todayDone ? todayKey : addDays(todayKey, -1);
  while (ok(cursor)) {
    current++;
    cursor = addDays(cursor, -1);
  }
  final keys = daily.keys.where(ok).toList()..sort();
  var longest = 0;
  var run = 0;
  String? prev;
  for (final k in keys) {
    if (prev != null && addDays(prev, 1) == k) {
      run++;
    } else {
      run = 1;
    }
    if (run > longest) longest = run;
    prev = k;
  }
  if (current > longest) longest = current;
  return StreakInfo(current, longest, todayDone);
}

/// XP: 1 XP per studied minute. Level L needs 50 * L * (L - 1) XP.
int xpForLevel(int level) => 50 * level * (level - 1);

int levelForXp(int xp) {
  var l = 1;
  while (xpForLevel(l + 1) <= xp) {
    l++;
  }
  return l;
}

String titleForLevel(int level) {
  if (level >= 40) return 'Legend';
  if (level >= 30) return 'Grandmaster';
  if (level >= 20) return 'Master';
  if (level >= 15) return 'Expert';
  if (level >= 10) return 'Scholar';
  if (level >= 5) return 'Apprentice';
  return 'Novice';
}

class Insight {
  final String emoji;
  final String title;
  final String body;
  const Insight(this.emoji, this.title, this.body);
}

List<Insight> buildInsights({
  required Map<String, int> daily,
  required List<int> hourBuckets,
  required String todayKey,
  required List<Subject> subjects,
  required Map<String, Map<String, int>> subjectDaily,
  required int sessionCount,
  required int sessionMs,
}) {
  final out = <Insight>[];
  int sumRange(int fromDaysAgo, int toDaysAgo) {
    var s = 0;
    for (var i = fromDaysAgo; i <= toDaysAgo; i++) {
      s += daily[addDays(todayKey, -i)] ?? 0;
    }
    return s;
  }

  final thisWeek = sumRange(0, 6);
  final lastWeek = sumRange(7, 13);
  if (thisWeek > 0 || lastWeek > 0) {
    if (lastWeek == 0) {
      out.add(Insight('🚀', 'Fresh momentum',
          'You studied ${formatDuration(thisWeek)} in the last 7 days. Keep it rolling!'));
    } else {
      final pct = ((thisWeek - lastWeek) / lastWeek * 100).round();
      out.add(pct >= 0
          ? Insight('📈', '+$pct% vs last week',
              '${formatDuration(thisWeek)} this week vs ${formatDuration(lastWeek)} the week before.')
          : Insight('📉', '$pct% vs last week',
              '${formatDuration(thisWeek)} this week vs ${formatDuration(lastWeek)}. A short session today helps!'));
    }
  }

  final totalHour = hourBuckets.fold<int>(0, (a, b) => a + b);
  if (totalHour > 0) {
    var best = 0;
    for (var h = 1; h < 24; h++) {
      if (hourBuckets[h] > hourBuckets[best]) best = h;
    }
    String label(int h) {
      final hh = h % 12 == 0 ? 12 : h % 12;
      return '$hh ${h < 12 ? 'AM' : 'PM'}';
    }

    out.add(Insight(best >= 20 || best < 5 ? '🦉' : (best < 11 ? '🌅' : '☀️'), 'Peak hour: ${label(best)}',
        'You focus most between ${label(best)} and ${label((best + 1) % 24)}. Schedule hard topics there.'));
  }

  // Best weekday over the last 12 weeks.
  final weekday = List.filled(7, 0);
  for (var i = 0; i < 84; i++) {
    final k = addDays(todayKey, -i);
    weekday[dateOfKey(k).weekday - 1] += daily[k] ?? 0;
  }
  if (weekday.any((v) => v > 0)) {
    var b = 0;
    for (var i = 1; i < 7; i++) {
      if (weekday[i] > weekday[b]) b = i;
    }
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    out.add(Insight('📅', '${names[b]}s are your power day',
        'Over the last 12 weeks you studied the most on ${names[b]}s.'));
  }

  // Top subject this week.
  String? topId;
  var topMs = 0;
  subjectDaily.forEach((sid, days) {
    var s = 0;
    for (var i = 0; i < 7; i++) {
      s += days[addDays(todayKey, -i)] ?? 0;
    }
    if (s > topMs) {
      topMs = s;
      topId = sid;
    }
  });
  if (topId != null) {
    final sub = subjects.where((s) => s.id == topId).firstOrNull;
    if (sub != null) {
      out.add(Insight(sub.emoji, '${sub.name} leads this week',
          '${formatDuration(topMs)} in the last 7 days.'));
    }
  }

  // Neglected subject: studied before but not in 7+ days.
  for (final s in subjects) {
    final days = subjectDaily[s.id];
    if (days == null || days.isEmpty) continue;
    final last = (days.keys.toList()..sort()).last;
    final gap = dateOfKey(todayKey).difference(dateOfKey(last)).inDays;
    if (gap >= 7) {
      out.add(Insight('⏰', '${s.name} misses you', 'Last studied $gap days ago.'));
      break;
    }
  }

  if (sessionCount > 0) {
    out.add(Insight('⏱️', 'Avg session ${formatDuration(sessionMs ~/ sessionCount)}',
        'Across $sessionCount timed sessions.'));
  }
  return out;
}

const motivationalQuotes = <String>[
  'Small steps every day add up to big results.',
  'Discipline is choosing what you want most over what you want now.',
  'You don\'t have to be great to start, but you have to start to be great.',
  'Focus on progress, not perfection.',
  'The secret of getting ahead is getting started.',
  'Deep work is a superpower. Use it.',
  'One more chapter. Future you says thanks.',
  'Consistency beats intensity.',
  'Study now, shine later.',
  'Every expert was once a beginner.',
];
