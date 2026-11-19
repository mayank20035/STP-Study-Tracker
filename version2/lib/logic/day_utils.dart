import 'package:intl/intl.dart';

/// A "study day" starts at [dayStartHour] (default 5 AM, like v1), so a late
/// night session at 1 AM still counts for the previous day.
final DateFormat _keyFormat = DateFormat('yyyy-MM-dd');

String dayKeyFor(DateTime t, int dayStartHour) {
  final shifted = DateTime(t.year, t.month, t.day, t.hour - dayStartHour, t.minute, t.second);
  return _keyFormat.format(shifted);
}

String dayKeyForMs(int ms, int dayStartHour) =>
    dayKeyFor(DateTime.fromMillisecondsSinceEpoch(ms), dayStartHour);

/// Calendar date (midnight) represented by a day key.
DateTime dateOfKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String keyOfDate(DateTime d) => _keyFormat.format(d);

String addDays(String key, int days) {
  final d = dateOfKey(key);
  return keyOfDate(DateTime(d.year, d.month, d.day + days));
}

/// The real moment the study day [key] begins.
DateTime dayStartMoment(String key, int dayStartHour) {
  final d = dateOfKey(key);
  return DateTime(d.year, d.month, d.day, dayStartHour);
}

/// Splits the interval [startMs, endMs) into per-study-day chunks.
/// Fixes the v1 bug where a session crossing the reset hour was credited
/// entirely to the day the timer was stopped.
Map<String, int> splitByDay(int startMs, int endMs, int dayStartHour) {
  final out = <String, int>{};
  var cursor = startMs;
  var guard = 0;
  while (cursor < endMs && guard < 400) {
    guard++;
    final key = dayKeyForMs(cursor, dayStartHour);
    final next = dayStartMoment(addDays(key, 1), dayStartHour).millisecondsSinceEpoch;
    final segEnd = next < endMs ? next : endMs;
    out[key] = (out[key] ?? 0) + (segEnd - cursor);
    cursor = segEnd;
  }
  return out;
}

/// Splits [startMs, endMs) into clock-hour buckets (0..23).
void addToHourBuckets(List<int> buckets, int startMs, int endMs) {
  var cursor = startMs;
  var guard = 0;
  while (cursor < endMs && guard < 2000) {
    guard++;
    final t = DateTime.fromMillisecondsSinceEpoch(cursor);
    final nextHour = DateTime(t.year, t.month, t.day, t.hour + 1).millisecondsSinceEpoch;
    final segEnd = nextHour < endMs ? nextHour : endMs;
    buckets[t.hour] += segEnd - cursor;
    cursor = segEnd;
  }
}

String formatClock(int ms) {
  if (ms < 0) ms = 0;
  final s = ms ~/ 1000;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(h)}:${two(m)}:${two(sec)}';
}

String formatShortClock(int ms) {
  if (ms < 0) ms = 0;
  final s = (ms / 1000).ceil();
  final m = s ~/ 60;
  final sec = s % 60;
  return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

/// "2h 15m", "45m", "0m"
String formatDuration(int ms) {
  if (ms <= 0) return '0m';
  final totalMin = ms ~/ 60000;
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
  if (totalMin == 0) return '${ms ~/ 1000}s';
  return '${m}m';
}

String formatHours(int ms, {int decimals = 1}) => (ms / 3600000).toStringAsFixed(decimals);

String prettyDayKey(String key, String todayKey) {
  if (key == todayKey) return 'Today';
  if (key == addDays(todayKey, -1)) return 'Yesterday';
  return DateFormat('EEE, d MMM yyyy').format(dateOfKey(key));
}
