import 'package:flutter/material.dart';

/// Generates a reasonably unique id without extra dependencies.
int _idCounter = 0;
String newId() {
  _idCounter = (_idCounter + 1) % 100000;
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_idCounter.toRadixString(36)}';
}

class Medals {
  final int gold;
  final int silver;
  final int bronze;
  const Medals({this.gold = 0, this.silver = 0, this.bronze = 0});

  Medals operator +(Medals o) =>
      Medals(gold: gold + o.gold, silver: silver + o.silver, bronze: bronze + o.bronze);

  int get total => gold + silver + bronze;

  Map<String, dynamic> toJson() => {'gold': gold, 'silver': silver, 'bronze': bronze};
  factory Medals.fromJson(Map<String, dynamic>? j) => Medals(
        gold: (j?['gold'] as num?)?.toInt() ?? 0,
        silver: (j?['silver'] as num?)?.toInt() ?? 0,
        bronze: (j?['bronze'] as num?)?.toInt() ?? 0,
      );
}

class Chapter {
  final String id;
  String name;
  bool completed;
  bool hidden;

  /// Time imported from v1 that cannot be attributed to a specific day.
  int legacyMs;

  Chapter({
    required this.id,
    required this.name,
    this.completed = false,
    this.hidden = false,
    this.legacyMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'completed': completed,
        'hidden': hidden,
        'legacyMs': legacyMs,
      };

  factory Chapter.fromJson(Map<String, dynamic> j) => Chapter(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        completed: j['completed'] as bool? ?? false,
        hidden: j['hidden'] as bool? ?? false,
        legacyMs: (j['legacyMs'] as num?)?.toInt() ?? 0,
      );
}

const subjectPalette = <int>[
  0xFF6366F1, // indigo
  0xFF8B5CF6, // violet
  0xFFEC4899, // pink
  0xFFEF4444, // red
  0xFFF97316, // orange
  0xFFF59E0B, // amber
  0xFF10B981, // emerald
  0xFF14B8A6, // teal
  0xFF06B6D4, // cyan
  0xFF3B82F6, // blue
  0xFF64748B, // slate
  0xFF84CC16, // lime
];

const subjectEmojis = <String>[
  '📘', '📗', '📕', '📙', '🧮', '🔬', '🧪', '🧬', '💻', '🌍', '📜', '🎨',
  '🎵', '🏋️', '🧠', '✍️', '📊', '⚖️', '🗣️', '🎯', '🚀', '🎮', '📐', '💡',
];

class Subject {
  final String id;
  String name;
  String emoji;
  int color;
  double targetHours;
  String category;
  String note;
  List<Chapter> chapters;
  Medals legacyMedals;

  /// Time imported from v1 not linked to any chapter.
  int legacyMs;

  Subject({
    required this.id,
    required this.name,
    this.emoji = '📘',
    this.color = 0xFF6366F1,
    this.targetHours = 100,
    this.category = '',
    this.note = '',
    List<Chapter>? chapters,
    this.legacyMedals = const Medals(),
    this.legacyMs = 0,
  }) : chapters = chapters ?? [];

  Color get colorValue => Color(color);

  int get completedChapters => chapters.where((c) => c.completed).length;

  int get legacyTotalMs => legacyMs + chapters.fold(0, (a, c) => a + c.legacyMs);

  Chapter? chapterById(String? id) {
    if (id == null) return null;
    for (final c in chapters) {
      if (c.id == id) return c;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'color': color,
        'targetHours': targetHours,
        'category': category,
        'note': note,
        'chapters': chapters.map((c) => c.toJson()).toList(),
        'legacyMedals': legacyMedals.toJson(),
        'legacyMs': legacyMs,
      };

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Subject',
        emoji: j['emoji'] as String? ?? '📘',
        color: (j['color'] as num?)?.toInt() ?? 0xFF6366F1,
        targetHours: (j['targetHours'] as num?)?.toDouble() ?? 100,
        category: j['category'] as String? ?? '',
        note: j['note'] as String? ?? '',
        chapters: ((j['chapters'] as List?) ?? [])
            .map((c) => Chapter.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList(),
        legacyMedals: Medals.fromJson(
            j['legacyMedals'] == null ? null : Map<String, dynamic>.from(j['legacyMedals'] as Map)),
        legacyMs: (j['legacyMs'] as num?)?.toInt() ?? 0,
      );
}

/// A single continuous block of study time.
class StudySession {
  final String id;
  String subjectId;
  String? chapterId;
  int startMs;
  int endMs;
  bool manual;
  bool pomodoro;

  StudySession({
    required this.id,
    required this.subjectId,
    this.chapterId,
    required this.startMs,
    required this.endMs,
    this.manual = false,
    this.pomodoro = false,
  });

  int get durationMs => endMs - startMs;
  DateTime get start => DateTime.fromMillisecondsSinceEpoch(startMs);
  DateTime get end => DateTime.fromMillisecondsSinceEpoch(endMs);

  Map<String, dynamic> toJson() => {
        'id': id,
        's': subjectId,
        'c': chapterId,
        'a': startMs,
        'b': endMs,
        if (manual) 'm': true,
        if (pomodoro) 'p': true,
      };

  factory StudySession.fromJson(Map<String, dynamic> j) => StudySession(
        id: j['id'] as String,
        subjectId: j['s'] as String,
        chapterId: j['c'] as String?,
        startMs: (j['a'] as num).toInt(),
        endMs: (j['b'] as num).toInt(),
        manual: j['m'] as bool? ?? false,
        pomodoro: j['p'] as bool? ?? false,
      );
}

class LevelGoal {
  final String id;
  String label;
  int hours;
  LevelGoal({required this.id, required this.label, required this.hours});

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'hours': hours};
  factory LevelGoal.fromJson(Map<String, dynamic> j) => LevelGoal(
        id: j['id'].toString(),
        label: j['label'] as String? ?? 'Goal',
        hours: (j['hours'] as num?)?.toInt() ?? 1000,
      );
}

/// A timer that is currently counting (survives app restarts).
class ActiveTimer {
  final String subjectId;
  final String? chapterId;
  final int startMs;
  const ActiveTimer({required this.subjectId, this.chapterId, required this.startMs});

  Map<String, dynamic> toJson() => {'s': subjectId, 'c': chapterId, 'a': startMs};
  factory ActiveTimer.fromJson(Map<String, dynamic> j) => ActiveTimer(
        subjectId: j['s'] as String,
        chapterId: j['c'] as String?,
        startMs: (j['a'] as num).toInt(),
      );
}

enum PomodoroPhase { work, shortBreak, longBreak }

class PomodoroState {
  final String subjectId;
  final String? chapterId;
  final PomodoroPhase phase;
  final int phaseStartMs;

  /// Number of work blocks finished in this pomodoro run.
  final int completedWork;

  /// When the pomodoro is paused, the remaining ms of the current phase.
  final int? pausedRemainingMs;

  const PomodoroState({
    required this.subjectId,
    this.chapterId,
    required this.phase,
    required this.phaseStartMs,
    this.completedWork = 0,
    this.pausedRemainingMs,
  });

  bool get isPaused => pausedRemainingMs != null;
  bool get isBreak => phase != PomodoroPhase.work;

  PomodoroState copyWith({
    PomodoroPhase? phase,
    int? phaseStartMs,
    int? completedWork,
    int? pausedRemainingMs,
    bool clearPaused = false,
  }) =>
      PomodoroState(
        subjectId: subjectId,
        chapterId: chapterId,
        phase: phase ?? this.phase,
        phaseStartMs: phaseStartMs ?? this.phaseStartMs,
        completedWork: completedWork ?? this.completedWork,
        pausedRemainingMs: clearPaused ? null : (pausedRemainingMs ?? this.pausedRemainingMs),
      );

  Map<String, dynamic> toJson() => {
        's': subjectId,
        'c': chapterId,
        'phase': phase.index,
        'a': phaseStartMs,
        'n': completedWork,
        'r': pausedRemainingMs,
      };

  factory PomodoroState.fromJson(Map<String, dynamic> j) => PomodoroState(
        subjectId: j['s'] as String,
        chapterId: j['c'] as String?,
        phase: PomodoroPhase.values[(j['phase'] as num).toInt()],
        phaseStartMs: (j['a'] as num).toInt(),
        completedWork: (j['n'] as num?)?.toInt() ?? 0,
        pausedRemainingMs: (j['r'] as num?)?.toInt(),
      );
}

class AppSettings {
  ThemeMode themeMode;
  int accentIndex;
  int dailyGoalMinutes;
  int dayStartHour;
  int pomodoroWorkMin;
  int pomodoroShortBreakMin;
  int pomodoroLongBreakMin;
  int pomodoroCyclesBeforeLong;
  bool pomodoroAutoStart;
  int streakMinMinutes;
  String activeGoalId;

  /// Subjects counted in the home "level" total. `null` = all subjects.
  List<String>? homeFilterIds;

  AppSettings({
    this.themeMode = ThemeMode.system,
    this.accentIndex = 0,
    this.dailyGoalMinutes = 180,
    this.dayStartHour = 5,
    this.pomodoroWorkMin = 25,
    this.pomodoroShortBreakMin = 5,
    this.pomodoroLongBreakMin = 15,
    this.pomodoroCyclesBeforeLong = 4,
    this.pomodoroAutoStart = true,
    this.streakMinMinutes = 15,
    this.activeGoalId = '1',
    this.homeFilterIds,
  });

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.index,
        'accentIndex': accentIndex,
        'dailyGoalMinutes': dailyGoalMinutes,
        'dayStartHour': dayStartHour,
        'pomodoroWorkMin': pomodoroWorkMin,
        'pomodoroShortBreakMin': pomodoroShortBreakMin,
        'pomodoroLongBreakMin': pomodoroLongBreakMin,
        'pomodoroCyclesBeforeLong': pomodoroCyclesBeforeLong,
        'pomodoroAutoStart': pomodoroAutoStart,
        'streakMinMinutes': streakMinMinutes,
        'activeGoalId': activeGoalId,
        'homeFilterIds': homeFilterIds,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        themeMode: ThemeMode.values[((j['themeMode'] as num?)?.toInt() ?? 0).clamp(0, 2)],
        accentIndex: (j['accentIndex'] as num?)?.toInt() ?? 0,
        dailyGoalMinutes: (j['dailyGoalMinutes'] as num?)?.toInt() ?? 180,
        dayStartHour: (j['dayStartHour'] as num?)?.toInt() ?? 5,
        pomodoroWorkMin: (j['pomodoroWorkMin'] as num?)?.toInt() ?? 25,
        pomodoroShortBreakMin: (j['pomodoroShortBreakMin'] as num?)?.toInt() ?? 5,
        pomodoroLongBreakMin: (j['pomodoroLongBreakMin'] as num?)?.toInt() ?? 15,
        pomodoroCyclesBeforeLong: (j['pomodoroCyclesBeforeLong'] as num?)?.toInt() ?? 4,
        pomodoroAutoStart: j['pomodoroAutoStart'] as bool? ?? true,
        streakMinMinutes: (j['streakMinMinutes'] as num?)?.toInt() ?? 15,
        activeGoalId: j['activeGoalId']?.toString() ?? '1',
        homeFilterIds: (j['homeFilterIds'] as List?)?.map((e) => e.toString()).toList(),
      );
}

class UserProfile {
  String name;
  String avatar;
  List<String> traits;
  UserProfile({this.name = 'Student', this.avatar = '🦊', List<String>? traits})
      : traits = traits ?? [];

  Map<String, dynamic> toJson() => {'name': name, 'avatar': avatar, 'traits': traits};
  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        name: j['name'] as String? ?? 'Student',
        avatar: j['avatar'] as String? ?? '🦊',
        traits: (j['traits'] as List?)?.map((e) => e.toString()).toList(),
      );
}

const traitOptions = <String>[
  'Night Owl 🦉', 'Early Bird ☀️', 'Visual Learner 👁️', 'Note Taker 📝',
  'Procrastinator 😅', 'Consistent 🏃', 'Crammer 📚', 'Techie 💻',
  'Coffee Lover ☕', 'Bookworm 🐛', 'Problem Solver 🧩', 'Music While Studying 🎧',
];

const avatarOptions = <String>[
  '🦊', '🐼', '🦉', '🐯', '🐨', '🐸', '🦁', '🐙', '🦄', '🐧', '🐻', '🐺',
  '🧑‍🎓', '👩‍💻', '👨‍🔬', '🧙', '🥷', '🤖', '👽', '🐉',
];

/// One line in the To-Do book: study [subjectId] for [targetMs] that day.
class PlanTask {
  final String id;
  final String subjectId;
  int targetMs;

  PlanTask({required this.id, required this.subjectId, required this.targetMs});

  Map<String, dynamic> toJson() => {'id': id, 's': subjectId, 't': targetMs};
  factory PlanTask.fromJson(Map<String, dynamic> j) => PlanTask(
        id: j['id'] as String,
        subjectId: j['s'] as String,
        targetMs: (j['t'] as num).toInt(),
      );
}

/// A single page of the To-Do book.
class DayPlan {
  final String dayKey;
  List<PlanTask> tasks;
  String note;
  int? mood;

  DayPlan({required this.dayKey, List<PlanTask>? tasks, this.note = '', this.mood})
      : tasks = tasks ?? [];

  bool get isEmpty => tasks.isEmpty && note.isEmpty && mood == null;

  PlanTask? taskById(String? id) {
    if (id == null) return null;
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  PlanTask? taskForSubject(String subjectId) {
    for (final t in tasks) {
      if (t.subjectId == subjectId) return t;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'd': dayKey,
        'tasks': tasks.map((t) => t.toJson()).toList(),
        if (note.isNotEmpty) 'note': note,
        if (mood != null) 'mood': mood,
      };

  factory DayPlan.fromJson(Map<String, dynamic> j) => DayPlan(
        dayKey: j['d'] as String,
        tasks: ((j['tasks'] as List?) ?? [])
            .map((e) => PlanTask.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        note: j['note'] as String? ?? '',
        mood: (j['mood'] as num?)?.toInt(),
      );
}

/// A target alarm that is ringing (or rang while the app was closed).
class AlarmState {
  final String taskId;
  final String dayKey;
  final String subjectId;
  final int reachedAtMs;
  const AlarmState({
    required this.taskId,
    required this.dayKey,
    required this.subjectId,
    required this.reachedAtMs,
  });

  Map<String, dynamic> toJson() => {'t': taskId, 'd': dayKey, 's': subjectId, 'a': reachedAtMs};
  factory AlarmState.fromJson(Map<String, dynamic> j) => AlarmState(
        taskId: j['t'] as String,
        dayKey: j['d'] as String,
        subjectId: j['s'] as String,
        reachedAtMs: (j['a'] as num).toInt(),
      );
}

/// Everything that is persisted.
class AppData {
  List<Subject> subjects;
  List<StudySession> sessions;
  List<LevelGoal> goals;
  List<String> categories;
  AppSettings settings;
  UserProfile profile;
  ActiveTimer? activeTimer;
  PomodoroState? pomodoro;
  int pomodorosCompleted;
  List<String> seenAchievements;
  Map<String, DayPlan> plans;
  String? selectedTaskId;
  String? selectedTaskDay;
  AlarmState? alarm;

  AppData({
    List<Subject>? subjects,
    List<StudySession>? sessions,
    List<LevelGoal>? goals,
    List<String>? categories,
    AppSettings? settings,
    UserProfile? profile,
    this.activeTimer,
    this.pomodoro,
    this.pomodorosCompleted = 0,
    List<String>? seenAchievements,
    Map<String, DayPlan>? plans,
    this.selectedTaskId,
    this.selectedTaskDay,
    this.alarm,
  })  : plans = plans ?? {},
        subjects = subjects ?? [],
        sessions = sessions ?? [],
        goals = goals ??
            [
              LevelGoal(id: '1', label: 'Beginner', hours: 1000),
              LevelGoal(id: '2', label: 'Intermediate', hours: 5000),
              LevelGoal(id: '3', label: 'Expert', hours: 10000),
            ],
        categories = categories ?? ['Exam Prep', 'Skills', 'Hobby', 'Workout'],
        settings = settings ?? AppSettings(),
        profile = profile ?? UserProfile(),
        seenAchievements = seenAchievements ?? [];

  static const int schemaVersion = 2;

  Map<String, dynamic> toJson() => {
        'app': 'STP',
        'schema': schemaVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'subjects': subjects.map((s) => s.toJson()).toList(),
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'goals': goals.map((g) => g.toJson()).toList(),
        'categories': categories,
        'settings': settings.toJson(),
        'profile': profile.toJson(),
        'activeTimer': activeTimer?.toJson(),
        'pomodoro': pomodoro?.toJson(),
        'pomodorosCompleted': pomodorosCompleted,
        'seenAchievements': seenAchievements,
        'plans': plans.values.where((p) => !p.isEmpty).map((p) => p.toJson()).toList(),
        'selectedTaskId': selectedTaskId,
        'selectedTaskDay': selectedTaskDay,
        'alarm': alarm?.toJson(),
      };

  factory AppData.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? m(dynamic v) => v == null ? null : Map<String, dynamic>.from(v as Map);
    return AppData(
      subjects: ((j['subjects'] as List?) ?? []).map((e) => Subject.fromJson(m(e)!)).toList(),
      sessions: ((j['sessions'] as List?) ?? []).map((e) => StudySession.fromJson(m(e)!)).toList(),
      goals: (j['goals'] as List?)?.map((e) => LevelGoal.fromJson(m(e)!)).toList(),
      categories: (j['categories'] as List?)?.map((e) => e.toString()).toList(),
      settings: j['settings'] == null ? null : AppSettings.fromJson(m(j['settings'])!),
      profile: j['profile'] == null ? null : UserProfile.fromJson(m(j['profile'])!),
      activeTimer: j['activeTimer'] == null ? null : ActiveTimer.fromJson(m(j['activeTimer'])!),
      pomodoro: j['pomodoro'] == null ? null : PomodoroState.fromJson(m(j['pomodoro'])!),
      pomodorosCompleted: (j['pomodorosCompleted'] as num?)?.toInt() ?? 0,
      seenAchievements: (j['seenAchievements'] as List?)?.map((e) => e.toString()).toList(),
      plans: {
        for (final p in ((j['plans'] as List?) ?? []).map((e) => DayPlan.fromJson(m(e)!))) p.dayKey: p,
      },
      selectedTaskId: j['selectedTaskId'] as String?,
      selectedTaskDay: j['selectedTaskDay'] as String?,
      alarm: j['alarm'] == null ? null : AlarmState.fromJson(m(j['alarm'])!),
    );
  }
}
