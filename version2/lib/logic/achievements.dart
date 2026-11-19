import '../models/models.dart';
import 'day_utils.dart';

class AchievementContext {
  final int totalMs;
  final int sessionCount;
  final int longestSessionMs;
  final int currentStreak;
  final int longestStreak;
  final Map<String, int> daily;
  final int dailyGoalMs;
  final int pomodorosCompleted;
  final List<Subject> subjects;
  final Map<String, int> subjectTotal;
  final bool hasNightSession;
  final bool hasEarlySession;

  const AchievementContext({
    required this.totalMs,
    required this.sessionCount,
    required this.longestSessionMs,
    required this.currentStreak,
    required this.longestStreak,
    required this.daily,
    required this.dailyGoalMs,
    required this.pomodorosCompleted,
    required this.subjects,
    required this.subjectTotal,
    required this.hasNightSession,
    required this.hasEarlySession,
  });

  double get totalHours => totalMs / 3600000;
  int get maxDayMs => daily.values.fold(0, (a, b) => b > a ? b : a);
  int get goalDays => dailyGoalMs <= 0 ? 0 : daily.values.where((v) => v >= dailyGoalMs).length;
  int get studiedSubjects => subjectTotal.values.where((v) => v >= 600000).length;

  bool get weekendWarrior {
    for (final k in daily.keys) {
      final d = dateOfKey(k);
      if (d.weekday == DateTime.saturday && (daily[k] ?? 0) > 0) {
        if ((daily[addDays(k, 1)] ?? 0) > 0) return true;
      }
    }
    return false;
  }

  bool get syllabusMaster =>
      subjects.any((s) => s.chapters.length >= 3 && s.chapters.every((c) => c.completed));
}

class Achievement {
  final String id;
  final String emoji;
  final String title;
  final String description;

  /// Returns progress in 0..1 (1 = unlocked).
  final double Function(AchievementContext c) progress;

  const Achievement(this.id, this.emoji, this.title, this.description, this.progress);
}

double _r(num value, num target) => target <= 0 ? 1 : (value / target).clamp(0, 1).toDouble();

final List<Achievement> allAchievements = [
  Achievement('first', '🌱', 'First Step', 'Complete your first study session',
      (c) => _r(c.sessionCount, 1)),
  Achievement('h10', '⏳', 'Getting Serious', 'Study 10 hours in total', (c) => _r(c.totalHours, 10)),
  Achievement('h50', '📚', 'Half Century', 'Study 50 hours in total', (c) => _r(c.totalHours, 50)),
  Achievement('h100', '💯', '100 Hour Club', 'Study 100 hours in total', (c) => _r(c.totalHours, 100)),
  Achievement('h500', '🏛️', 'Scholar', 'Study 500 hours in total', (c) => _r(c.totalHours, 500)),
  Achievement('h1000', '👑', 'Grandmaster', 'Study 1000 hours in total', (c) => _r(c.totalHours, 1000)),
  Achievement('s3', '🔥', 'On Fire', 'Reach a 3-day streak', (c) => _r(c.longestStreak, 3)),
  Achievement('s7', '⚡', 'Unstoppable Week', 'Reach a 7-day streak', (c) => _r(c.longestStreak, 7)),
  Achievement('s30', '🌋', 'Habit Formed', 'Reach a 30-day streak', (c) => _r(c.longestStreak, 30)),
  Achievement('marathon', '🏃', 'Marathon', 'One session of 3+ hours',
      (c) => _r(c.longestSessionMs, 3 * 3600000)),
  Achievement('bigday', '🌞', 'Big Day', 'Study 8 hours in a single day',
      (c) => _r(c.maxDayMs, 8 * 3600000)),
  Achievement('goal7', '🎯', 'Goal Getter', 'Hit your daily goal on 7 days', (c) => _r(c.goalDays, 7)),
  Achievement('night', '🦉', 'Night Owl', 'Study 10+ min between midnight and 4 AM',
      (c) => c.hasNightSession ? 1 : 0),
  Achievement('early', '🐦', 'Early Bird', 'Start a session between 5 and 7 AM',
      (c) => c.hasEarlySession ? 1 : 0),
  Achievement('tomato10', '🍅', 'Tomato Farmer', 'Complete 10 Pomodoros',
      (c) => _r(c.pomodorosCompleted, 10)),
  Achievement('tomato100', '🥫', 'Pomodoro Pro', 'Complete 100 Pomodoros',
      (c) => _r(c.pomodorosCompleted, 100)),
  Achievement('poly', '🧩', 'Polymath', 'Study 5 different subjects (10+ min each)',
      (c) => _r(c.studiedSubjects, 5)),
  Achievement('weekend', '🛡️', 'Weekend Warrior', 'Study on both Saturday and Sunday',
      (c) => c.weekendWarrior ? 1 : 0),
  Achievement('syllabus', '✅', 'Syllabus Slayer', 'Complete every chapter of a subject (3+ chapters)',
      (c) => c.syllabusMaster ? 1 : 0),
];
