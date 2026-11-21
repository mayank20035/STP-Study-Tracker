import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../logic/achievements.dart';
import '../logic/day_utils.dart';
import '../logic/stats.dart';
import '../models/models.dart';
import '../services/alarm_service.dart';
import '../services/storage_service.dart';

class PomodoroEvent {
  final int serial;
  final String message;
  const PomodoroEvent(this.serial, this.message);
}

class AchievementProgress {
  final Achievement achievement;
  final double progress;
  const AchievementProgress(this.achievement, this.progress);
  bool get unlocked => progress >= 1;
}

/// Result of editing the To-Do book.
enum PlanResult { ok, unknownSubject, invalidTarget, duplicateSubject, notFound }

enum TaskStatus { pending, inProgress, done }

enum PageStatus { empty, conquered, partial, missed, upcoming, today }

class StudyStore extends ChangeNotifier {
  StudyStore({
    StorageService? storage,
    AlarmScheduler? alarms,
    int Function()? clock,
    this.enableTicker = true,
  })  : _storage = storage ?? StorageService(),
        alarms = alarms ?? NoopAlarmScheduler(),
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final StorageService _storage;
  final AlarmScheduler alarms;
  final int Function() _clock;
  final bool enableTicker;

  /// Longest target allowed for one task.
  static const int maxTargetMs = 24 * 3600000;
  static const int minTargetMs = 60000;
  AppData _data = AppData();
  bool _loaded = false;
  Timer? _ticker;
  Timer? _saveDebounce;

  /// Minimum length of a timed session that gets recorded.
  static const int minSessionMs = 10000;

  final ValueNotifier<PomodoroEvent?> pomodoroEvents = ValueNotifier(null);
  final ValueNotifier<List<Achievement>> newAchievements = ValueNotifier(const []);
  int _eventSerial = 0;

  // ---------------------------------------------------------------- getters
  bool get isLoaded => _loaded;
  AppData get data => _data;
  List<Subject> get subjects => _data.subjects;
  List<StudySession> get sessions => _data.sessions;
  List<LevelGoal> get goals => _data.goals;
  List<String> get categories => _data.categories;
  AppSettings get settings => _data.settings;
  UserProfile get profile => _data.profile;
  ActiveTimer? get activeTimer => _data.activeTimer;
  PomodoroState? get pomodoro => _data.pomodoro;
  int get pomodorosCompleted => _data.pomodorosCompleted;

  int get nowMs => _clock();
  String get todayKey => dayKeyForMs(nowMs, settings.dayStartHour);

  Subject? subjectById(String? id) {
    if (id == null) return null;
    for (final s in subjects) {
      if (s.id == id) return s;
    }
    return null;
  }

  LevelGoal get activeGoal =>
      goals.firstWhere((g) => g.id == settings.activeGoalId, orElse: () => goals.first);

  // ---------------------------------------------------------------- lifecycle
  Future<void> load() async {
    _data = await _storage.load();
    if (_data.goals.isEmpty) _data.goals = AppData().goals;
    _validateRunningState();
    _loaded = true;
    _syncAchievementsSilently();
    _lastTickDay = todayKey;
    _advancePomodoro();
    _enforceLimits(fromResume: true);
    _syncAlarmSchedule(force: true);
    _verifyPersistedAlarm();
    if (enableTicker) _startTicker();
    notifyListeners();
  }

  /// Re-checks timers when the app returns to the foreground.
  void onResume() {
    if (!_loaded) return;
    _enforceLimits(fromResume: true);
    _verifyPersistedAlarm();
    tick();
  }

  void _validateRunningState() {
    final t = _data.activeTimer;
    if (t != null && subjectById(t.subjectId) == null) _data.activeTimer = null;
    final p = _data.pomodoro;
    if (p != null && subjectById(p.subjectId) == null) _data.pomodoro = null;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  String? _lastTickDay;

  /// Called every second (and directly by tests).
  void tick() {
    final day = todayKey;
    final dayChanged = _lastTickDay != null && _lastTickDay != day;
    _lastTickDay = day;
    if (dayChanged) {
      _invalidate();
      _enforceLimits();
      _changed();
    }
    if (_data.pomodoro != null) _advancePomodoro();
    if (_data.activeTimer != null) _enforceLimits();
    if (_data.activeTimer != null || _data.pomodoro != null || dayChanged) {
      notifyListeners();
    }
  }

  void _changed({bool sessionsChanged = false}) {
    if (sessionsChanged) _invalidate();
    _syncAlarmSchedule();
    notifyListeners();
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () => _storage.save(_data));
  }

  Future<void> flush() async {
    _saveDebounce?.cancel();
    if (_loaded) await _storage.save(_data);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _saveDebounce?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- stats
  StatsSnapshot? _snapshot;
  String? _snapshotKey;
  Map<String, int>? _chapterTodayCache;

  void _invalidate() {
    _snapshot = null;
    _chapterTodayCache = null;
  }

  StatsSnapshot get snapshot {
    final key = '$todayKey|${settings.dayStartHour}';
    if (_snapshot == null || _snapshotKey != key) {
      _snapshot = StatsSnapshot.compute(
        subjects: subjects,
        sessions: sessions,
        dayStartHour: settings.dayStartHour,
        todayKey: todayKey,
      );
      _snapshotKey = key;
      _chapterTodayCache = null;
    }
    return _snapshot!;
  }

  int get liveMs => activeTimer == null ? 0 : math.max<int>(0, nowMs - activeTimer!.startMs);

  Map<String, int> get _liveSplit => activeTimer == null
      ? const {}
      : splitByDay(activeTimer!.startMs, nowMs, settings.dayStartHour);

  /// Daily totals including the running timer.
  Map<String, int> get dailyWithLive {
    final out = Map<String, int>.from(snapshot.daily);
    _liveSplit.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
    return out;
  }

  int dayMs(String key) => (snapshot.daily[key] ?? 0) + (_liveSplit[key] ?? 0);
  int get todayMs => dayMs(todayKey);
  int get totalMs => snapshot.totalMs + liveMs;

  bool isRunning(String subjectId, [String? chapterId]) =>
      activeTimer != null &&
      activeTimer!.subjectId == subjectId &&
      (chapterId == null || activeTimer!.chapterId == chapterId);

  int subjectTotalMs(String id) =>
      (snapshot.subjectTotal[id] ?? 0) + (activeTimer?.subjectId == id ? liveMs : 0);

  int subjectDayMs(String id, String key) =>
      (snapshot.subjectDaily[id]?[key] ?? 0) +
      (activeTimer?.subjectId == id ? (_liveSplit[key] ?? 0) : 0);

  int subjectTodayMs(String id) => subjectDayMs(id, todayKey);

  int chapterTotalMs(String id) =>
      (snapshot.chapterTotal[id] ?? 0) + (activeTimer?.chapterId == id ? liveMs : 0);

  int chapterTodayMs(String id) {
    snapshot; // ensure fresh
    _chapterTodayCache ??= () {
      final m = <String, int>{};
      final t = todayKey;
      final dayStart = dayStartMoment(t, settings.dayStartHour).millisecondsSinceEpoch;
      for (final s in sessions) {
        if (s.chapterId == null || s.endMs <= dayStart) continue;
        final v = splitByDay(s.startMs, s.endMs, settings.dayStartHour)[t] ?? 0;
        if (v > 0) m[s.chapterId!] = (m[s.chapterId!] ?? 0) + v;
      }
      return m;
    }();
    return (_chapterTodayCache![id] ?? 0) +
        (activeTimer?.chapterId == id ? (_liveSplit[todayKey] ?? 0) : 0);
  }

  Medals medalsFor(String subjectId) => snapshot.medals[subjectId] ?? const Medals();

  StreakInfo get streak =>
      computeStreak(dailyWithLive, todayKey, settings.streakMinMinutes * 60000);

  int get xp => totalMs ~/ 60000;
  int get level => levelForXp(xp);

  bool isInHomeFilter(String id) => settings.homeFilterIds?.contains(id) ?? true;

  int get filteredTotalMs =>
      subjects.where((s) => isInHomeFilter(s.id)).fold(0, (a, s) => a + subjectTotalMs(s.id));

  /// Per-subject / per-chapter breakdown for a given study day.
  List<({Subject subject, Chapter? chapter, int ms})> breakdownForDay(String key) {
    final map = <String, int>{};
    void add(String sid, String? cid, int ms) {
      final k = '$sid|${cid ?? ''}';
      map[k] = (map[k] ?? 0) + ms;
    }

    for (final s in sessions) {
      final v = splitByDay(s.startMs, s.endMs, settings.dayStartHour)[key] ?? 0;
      if (v > 0) add(s.subjectId, s.chapterId, v);
    }
    final live = _liveSplit[key] ?? 0;
    if (live > 0) add(activeTimer!.subjectId, activeTimer!.chapterId, live);
    final out = <({Subject subject, Chapter? chapter, int ms})>[];
    map.forEach((k, ms) {
      final parts = k.split('|');
      final sub = subjectById(parts[0]);
      if (sub == null) return;
      out.add((subject: sub, chapter: sub.chapterById(parts[1].isEmpty ? null : parts[1]), ms: ms));
    });
    out.sort((a, b) => b.ms.compareTo(a.ms));
    return out;
  }

  List<Insight> get insights {
    var timedMs = 0;
    var timedCount = 0;
    for (final s in sessions) {
      if (!s.manual) {
        timedMs += s.durationMs;
        timedCount++;
      }
    }
    return buildInsights(
      daily: dailyWithLive,
      hourBuckets: snapshot.hourBuckets,
      todayKey: todayKey,
      subjects: subjects,
      subjectDaily: snapshot.subjectDaily,
      sessionCount: timedCount,
      sessionMs: timedMs,
    );
  }

  // ---------------------------------------------------------------- achievements
  List<AchievementProgress> get achievements {
    final st = streak;
    final ctx = AchievementContext(
      totalMs: totalMs,
      sessionCount: snapshot.sessionCount,
      longestSessionMs: snapshot.longestSessionMs,
      currentStreak: st.current,
      longestStreak: st.longest,
      daily: dailyWithLive,
      dailyGoalMs: settings.dailyGoalMinutes * 60000,
      pomodorosCompleted: pomodorosCompleted,
      subjects: subjects,
      subjectTotal: snapshot.subjectTotal,
      hasNightSession: snapshot.hasNightSession,
      hasEarlySession: snapshot.hasEarlySession,
    );
    return allAchievements.map((a) => AchievementProgress(a, a.progress(ctx))).toList();
  }

  void _syncAchievementsSilently() {
    final unlocked = achievements.where((a) => a.unlocked).map((a) => a.achievement.id);
    final seen = _data.seenAchievements.toSet()..addAll(unlocked);
    _data.seenAchievements = seen.toList();
  }

  void _checkNewAchievements() {
    final seen = _data.seenAchievements.toSet();
    final fresh = achievements
        .where((a) => a.unlocked && !seen.contains(a.achievement.id))
        .map((a) => a.achievement)
        .toList();
    if (fresh.isEmpty) return;
    _data.seenAchievements = [...seen, ...fresh.map((a) => a.id)];
    newAchievements.value = fresh;
  }

  // ---------------------------------------------------------------- timer
  void _recordSession(ActiveTimer t, int end, {bool pomodoro = false, bool force = false}) {
    final start = t.startMs;
    if (end - start < (force ? 1 : minSessionMs)) return;
    final sub = subjectById(t.subjectId);
    if (sub == null) return;
    _data.sessions.add(StudySession(
      id: newId(),
      subjectId: t.subjectId,
      chapterId: sub.chapterById(t.chapterId) == null ? null : t.chapterId,
      startMs: start,
      endMs: end,
      pomodoro: pomodoro,
      // Time studied for a picked task counts on that task's page, whichever
      // day it was studied on (catching up a missed day, or working ahead).
      planDay: t.isLinked ? t.planDay : null,
    ));
    _invalidate();
  }

  /// A new timer for [subjectId]. It is linked to the picked To-Do task when
  /// the subjects match and the task is not finished yet (then it stops and
  /// rings at the target); otherwise it is a free timer.
  ActiveTimer _newTimer(String subjectId, String? chapterId, int startMs) {
    final sel = selectedTask;
    final day = selectedTaskDay;
    final link = sel != null && day != null && sel.subjectId == subjectId && !isTaskDone(day, sel);
    return ActiveTimer(
      subjectId: subjectId,
      chapterId: chapterId,
      startMs: startMs,
      taskId: link ? sel.id : null,
      planDay: link ? day : null,
    );
  }

  /// The task the running timer counts toward, if it is linked to one.
  PlanTask? get linkedTask {
    final t = activeTimer;
    if (t == null || !t.isLinked) return null;
    return _data.plans[t.planDay]?.taskById(t.taskId);
  }

  /// Starts (or switches) the stopwatch. Only one timer runs at a time.
  /// Any subject can be timed; picking a To-Do task first is optional.
  void startTimer(String subjectId, [String? chapterId]) {
    if (subjectById(subjectId) == null) return;
    _stopEverything();
    _data.activeTimer = _newTimer(subjectId, chapterId, nowMs);
    _safeHaptic(HapticFeedback.lightImpact);
    alarms.ensurePermissions();
    _changed(sessionsChanged: true);
  }

  void stopTimer() {
    _stopEverything();
    _safeHaptic(HapticFeedback.lightImpact);
    _changed(sessionsChanged: true);
    _checkNewAchievements();
  }

  void toggleTimer(String subjectId, [String? chapterId]) {
    final t = activeTimer;
    if (t != null && t.subjectId == subjectId && t.chapterId == chapterId && pomodoro == null) {
      stopTimer();
      return;
    }
    startTimer(subjectId, chapterId);
  }

  void _safeHaptic(Future<void> Function() f) {
    try {
      f().catchError((_) {});
    } catch (_) {}
  }

  void _stopEverything() {
    final t = _data.activeTimer;
    if (t != null) _recordSession(t, nowMs, pomodoro: _data.pomodoro != null);
    _data.activeTimer = null;
    _data.pomodoro = null;
  }

  /// Ends the running session now and keeps timing in a fresh one that is
  /// (re)linked to the current pick, so earlier time keeps its page.
  void _relinkRunningTimer() {
    final t = _data.activeTimer;
    if (t == null) return;
    final now = nowMs;
    _recordSession(t, now, pomodoro: _data.pomodoro != null);
    _data.activeTimer = _newTimer(t.subjectId, t.chapterId, now);
  }

  // ---------------------------------------------------------------- pomodoro
  int phaseLengthMs(PomodoroPhase p) => switch (p) {
        PomodoroPhase.work => settings.pomodoroWorkMin * 60000,
        PomodoroPhase.shortBreak => settings.pomodoroShortBreakMin * 60000,
        PomodoroPhase.longBreak => settings.pomodoroLongBreakMin * 60000,
      };

  int get pomodoroRemainingMs {
    final p = pomodoro;
    if (p == null) return 0;
    if (p.isPaused) return p.pausedRemainingMs!;
    return math.max<int>(0, p.phaseStartMs + phaseLengthMs(p.phase) - nowMs);
  }

  void startPomodoro(String subjectId, [String? chapterId]) {
    if (subjectById(subjectId) == null) return;
    _stopEverything();
    final now = nowMs;
    _data.pomodoro = PomodoroState(
        subjectId: subjectId, chapterId: chapterId, phase: PomodoroPhase.work, phaseStartMs: now);
    _data.activeTimer = _newTimer(subjectId, chapterId, now);
    _safeHaptic(HapticFeedback.mediumImpact);
    alarms.ensurePermissions();
    _changed(sessionsChanged: true);
  }

  void pausePomodoro() {
    final p = pomodoro;
    if (p == null || p.isPaused) return;
    final remaining = pomodoroRemainingMs;
    final t = activeTimer;
    if (t != null) _recordSession(t, nowMs, pomodoro: true);
    _data.activeTimer = null;
    _data.pomodoro = p.copyWith(pausedRemainingMs: remaining);
    _changed(sessionsChanged: true);
  }

  void resumePomodoro() {
    final p = pomodoro;
    if (p == null || !p.isPaused) return;
    final now = nowMs;
    final start = now - (phaseLengthMs(p.phase) - p.pausedRemainingMs!);
    _data.pomodoro = p.copyWith(phaseStartMs: start, clearPaused: true);
    if (p.phase == PomodoroPhase.work) {
      _data.activeTimer = _newTimer(p.subjectId, p.chapterId, now);
    }
    _changed(sessionsChanged: true);
  }

  void skipPomodoroPhase() {
    final p = pomodoro;
    if (p == null) return;
    final now = nowMs;
    _data.pomodoro = p.copyWith(
        phaseStartMs: now - phaseLengthMs(p.phase), clearPaused: true);
    if (p.isPaused && p.phase == PomodoroPhase.work) {
      // Skipping a paused work block: nothing to record.
      _data.activeTimer = null;
    }
    _advancePomodoro(countSkippedWork: false);
    _changed(sessionsChanged: true);
  }

  void stopPomodoro() => stopTimer();

  void _advancePomodoro({bool countSkippedWork = true}) {
    var p = _data.pomodoro;
    if (p == null || p.isPaused) return;
    final now = nowMs;
    var changed = false;
    String? message;
    var guard = 0;
    while (p != null && !p.isPaused && now >= p.phaseStartMs + phaseLengthMs(p.phase) && guard < 50) {
      guard++;
      changed = true;
      final phaseEnd = p.phaseStartMs + phaseLengthMs(p.phase);
      if (p.phase == PomodoroPhase.work && _data.activeTimer != null) {
        final lim = _limitFor(_data.activeTimer!);
        if (lim.atMs <= phaseEnd) {
          // The task target (or the day) ends inside this focus block.
          _finishAt(lim);
          return;
        }
      }
      if (p.phase == PomodoroPhase.work) {
        final t = _data.activeTimer;
        if (t != null) {
          final end = phaseEnd < t.startMs ? t.startMs : phaseEnd;
          _recordSession(t, end, pomodoro: true);
        }
        _data.activeTimer = null;
        final done = p.completedWork + (countSkippedWork ? 1 : 0);
        if (countSkippedWork) _data.pomodorosCompleted++;
        final long = done > 0 && done % settings.pomodoroCyclesBeforeLong == 0;
        p = p.copyWith(
          phase: long ? PomodoroPhase.longBreak : PomodoroPhase.shortBreak,
          phaseStartMs: phaseEnd,
          completedWork: done,
        );
        message = !countSkippedWork
            ? '⏭️ Focus block skipped — break time.'
            : (long ? '🎉 Pomodoro done! Take a long break.' : '🍅 Pomodoro done! Short break time.');
      } else {
        if (settings.pomodoroAutoStart) {
          p = p.copyWith(phase: PomodoroPhase.work, phaseStartMs: phaseEnd);
          _data.activeTimer = _newTimer(p.subjectId, p.chapterId, phaseEnd);
          message = '💪 Break over — back to focus!';
        } else {
          p = p.copyWith(
              phase: PomodoroPhase.work,
              phaseStartMs: now,
              pausedRemainingMs: phaseLengthMs(PomodoroPhase.work));
          message = '☕ Break over. Tap play when ready.';
        }
      }
      countSkippedWork = true;
    }
    if (changed) {
      _data.pomodoro = p;
      _safeHaptic(HapticFeedback.heavyImpact);
      _safeHaptic(() => SystemSound.play(SystemSoundType.alert));
      if (message != null) pomodoroEvents.value = PomodoroEvent(++_eventSerial, message);
      _changed(sessionsChanged: true);
      _checkNewAchievements();
    }
  }

  // ---------------------------------------------------------------- to-do book
  /// The page for [dayKey] (an empty, unsaved page if nothing is planned).
  DayPlan planFor(String dayKey) => _data.plans[dayKey] ?? DayPlan(dayKey: dayKey);

  DayPlan _ensurePlan(String dayKey) =>
      _data.plans.putIfAbsent(dayKey, () => DayPlan(dayKey: dayKey));

  bool isPastDay(String dayKey) => dayKey.compareTo(todayKey) < 0;

  /// The page of the picked task (any day: missed, today or ahead), if any.
  String? get selectedTaskDay => _data.selectedTaskDay;

  /// The task picked in the To-Do book, if any.
  PlanTask? get selectedTask {
    final day = selectedTaskDay;
    if (day == null) return null;
    return _data.plans[day]?.taskById(_data.selectedTaskId);
  }

  bool isSelected(String dayKey, PlanTask t) => selectedTaskDay == dayKey && selectedTask?.id == t.id;

  /// Time counted toward a task: the subject's free time studied that day,
  /// plus all time studied while this task was picked.
  int taskProgressMs(String dayKey, PlanTask t) {
    var ms = snapshot.planDaily[t.subjectId]?[dayKey] ?? 0;
    final a = activeTimer;
    if (a != null && a.subjectId == t.subjectId) {
      if (a.isLinked) {
        if (a.planDay == dayKey) ms += liveMs;
      } else {
        ms += _liveSplit[dayKey] ?? 0;
      }
    }
    return ms;
  }

  int taskRemainingMs(String dayKey, PlanTask t) =>
      math.max<int>(0, t.targetMs - taskProgressMs(dayKey, t));

  bool isTaskDone(String dayKey, PlanTask t) => taskProgressMs(dayKey, t) >= t.targetMs;

  TaskStatus taskStatus(String dayKey, PlanTask t) {
    if (isTaskDone(dayKey, t)) return TaskStatus.done;
    return taskProgressMs(dayKey, t) > 0 ? TaskStatus.inProgress : TaskStatus.pending;
  }

  ({int done, int total, double percent}) pageScore(String dayKey) {
    final tasks = planFor(dayKey).tasks;
    if (tasks.isEmpty) return (done: 0, total: 0, percent: 0);
    var done = 0;
    var target = 0;
    var progress = 0;
    for (final t in tasks) {
      if (isTaskDone(dayKey, t)) done++;
      target += t.targetMs;
      progress += math.min(t.targetMs, taskProgressMs(dayKey, t));
    }
    return (done: done, total: tasks.length, percent: target == 0 ? 0 : progress / target);
  }

  PageStatus pageStatus(String dayKey) {
    final tasks = planFor(dayKey).tasks;
    final cmp = dayKey.compareTo(todayKey);
    if (cmp > 0) return PageStatus.upcoming;
    if (tasks.isEmpty) return cmp == 0 ? PageStatus.today : PageStatus.empty;
    final score = pageScore(dayKey);
    if (score.done == score.total) return PageStatus.conquered;
    if (cmp == 0) return PageStatus.today;
    return score.percent > 0 ? PageStatus.partial : PageStatus.missed;
  }

  PlanResult _validateTarget(int targetMs) =>
      targetMs < minTargetMs || targetMs > maxTargetMs ? PlanResult.invalidTarget : PlanResult.ok;

  /// Adds a subject to a page of the book: only existing subjects, one line
  /// per subject. Any page works, so time studied earlier can be added later.
  PlanResult addPlanTask(String dayKey, String subjectId, int targetMs) {
    if (subjectById(subjectId) == null) return PlanResult.unknownSubject;
    final v = _validateTarget(targetMs);
    if (v != PlanResult.ok) return v;
    final plan = _ensurePlan(dayKey);
    if (plan.taskForSubject(subjectId) != null) return PlanResult.duplicateSubject;
    plan.tasks.add(PlanTask(id: newId(), subjectId: subjectId, targetMs: targetMs));
    _changed();
    return PlanResult.ok;
  }

  PlanResult updatePlanTaskTarget(String dayKey, String taskId, int targetMs) {
    final task = _data.plans[dayKey]?.taskById(taskId);
    if (task == null) return PlanResult.notFound;
    final v = _validateTarget(targetMs);
    if (v != PlanResult.ok) return v;
    task.targetMs = targetMs;
    // Lowering the target under what is already studied finishes the task now.
    _enforceLimits(endAtNow: true);
    _changed();
    return PlanResult.ok;
  }

  PlanResult removePlanTask(String dayKey, String taskId) {
    final plan = _data.plans[dayKey];
    final task = plan?.taskById(taskId);
    if (plan == null || task == null) return PlanResult.notFound;
    if (_data.selectedTaskId == taskId && _data.selectedTaskDay == dayKey) {
      _data.selectedTaskId = null;
      _data.selectedTaskDay = null;
    }
    // A timer linked to this task keeps running as a free timer.
    if (activeTimer?.taskId == taskId) _relinkRunningTimer();
    plan.tasks.remove(task);
    if (_data.alarm?.taskId == taskId) {
      _data.alarm = null;
      alarms.cancel();
    }
    _changed(sessionsChanged: true);
    return PlanResult.ok;
  }

  void reorderPlanTasks(String dayKey, int oldIndex, int newIndex) {
    final plan = _data.plans[dayKey];
    if (plan == null) return;
    if (newIndex > oldIndex) newIndex--;
    plan.tasks.insert(newIndex, plan.tasks.removeAt(oldIndex));
    _changed();
  }

  void setDayNote(String dayKey, String note) {
    _ensurePlan(dayKey).note = note;
    _changed();
  }

  /// Number of tasks planned in the week that starts on [weekStart].
  int weekTaskCount(String weekStart) {
    var n = 0;
    for (var i = 0; i < 7; i++) {
      n += planFor(addDays(weekStart, i)).tasks.length;
    }
    return n;
  }

  /// Copies the tasks of the week starting [fromWeek] onto the same weekdays
  /// of the week starting [toWeek] (subject and study time only, no progress,
  /// notes or moods). Tasks already in the target week are kept; a subject
  /// that is already on a target page is skipped.
  ({int added, int skipped}) copyWeek(String fromWeek, String toWeek) {
    if (fromWeek == toWeek) return (added: 0, skipped: 0);
    var added = 0, skipped = 0;
    for (var i = 0; i < 7; i++) {
      final src = _data.plans[addDays(fromWeek, i)];
      if (src == null) continue;
      final dst = addDays(toWeek, i);
      for (final t in src.tasks) {
        if (subjectById(t.subjectId) == null) continue;
        if (planFor(dst).taskForSubject(t.subjectId) != null) {
          skipped++;
          continue;
        }
        _ensurePlan(dst).tasks.add(PlanTask(id: newId(), subjectId: t.subjectId, targetMs: t.targetMs));
        added++;
      }
    }
    if (added > 0) _changed();
    return (added: added, skipped: skipped);
  }

  void setDayMood(String dayKey, int? mood) {
    _ensurePlan(dayKey).mood = mood;
    _changed();
  }

  /// Picks a task on any page: a missed day, today or a future day. A timer
  /// for its subject then counts toward that page and stops (with an alarm)
  /// at the target. Returns false for finished and unknown tasks.
  bool selectTask(String dayKey, String taskId) {
    final task = _data.plans[dayKey]?.taskById(taskId);
    if (task == null || isTaskDone(dayKey, task)) return false;
    _data.selectedTaskId = task.id;
    _data.selectedTaskDay = dayKey;
    final t = activeTimer;
    if (t != null) {
      if (t.subjectId == task.subjectId) {
        _relinkRunningTimer();
      } else if (t.isLinked) {
        // The running timer belonged to the previously picked task.
        _stopEverything();
      }
    }
    _safeHaptic(HapticFeedback.selectionClick);
    _changed(sessionsChanged: true);
    return true;
  }

  /// Unpicks the task; a timer linked to it keeps running as a free timer.
  void clearSelection() {
    _data.selectedTaskId = null;
    _data.selectedTaskDay = null;
    if (activeTimer?.isLinked ?? false) _relinkRunningTimer();
    _changed(sessionsChanged: true);
  }

  /// The book page that was open last, so the book reopens there.
  String? get bookPage => _data.bookPage;

  void rememberBookPage(String dayKey) {
    if (_data.bookPage == dayKey) return;
    _data.bookPage = dayKey;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () => _storage.save(_data));
  }

  void _dropInvalidSelection() {
    final day = _data.selectedTaskDay;
    if (day != null && _data.plans[day]?.taskById(_data.selectedTaskId) == null) {
      _data.selectedTaskId = null;
      _data.selectedTaskDay = null;
    }
  }

  // ---------------------------------------------------------------- limits & alarm
  /// When the running timer must stop. A free timer never stops by itself;
  /// a linked timer stops at its task's target.
  ({int atMs, bool isTarget, PlanTask? task, String dayKey}) _limitFor(ActiveTimer t) {
    const never = 8640000000000000;
    final day = t.planDay;
    final task = t.isLinked ? _data.plans[day]?.taskById(t.taskId) : null;
    if (day == null || task == null || task.subjectId != t.subjectId) {
      return (atMs: never, isTarget: false, task: null, dayKey: day ?? todayKey);
    }
    final before = snapshot.planDaily[t.subjectId]?[day] ?? 0;
    final int reach = t.startMs + math.max<int>(0, task.targetMs - before);
    return (atMs: reach, isTarget: true, task: task, dayKey: day);
  }

  /// Time left before the running timer stops at its target (null = none).
  int? get timerRemainingMs {
    final t = activeTimer;
    if (t == null) return null;
    final lim = _limitFor(t);
    return lim.isTarget ? math.max<int>(0, lim.atMs - nowMs) : null;
  }

  void _enforceLimits({bool fromResume = false, bool endAtNow = false}) {
    final t = _data.activeTimer;
    if (t == null) return;
    final lim = _limitFor(t);
    if (nowMs < lim.atMs) return;
    _finishAt(lim, endAtNow: endAtNow);
  }

  void _finishAt(({int atMs, bool isTarget, PlanTask? task, String dayKey}) lim,
      {bool endAtNow = false}) {
    final t = _data.activeTimer;
    if (t == null) return;
    // End exactly when the target was reached, even if the app was closed;
    // after an edit, the time actually studied until now is kept.
    final end = endAtNow ? math.max(nowMs, t.startMs) : lim.atMs;
    _recordSession(t, end, pomodoro: _data.pomodoro != null, force: true);
    _data.activeTimer = null;
    _data.pomodoro = null;
    final sub = subjectById(t.subjectId);
    if (lim.isTarget) {
      _data.alarm = AlarmState(
        taskId: lim.task!.id,
        dayKey: lim.dayKey,
        subjectId: t.subjectId,
        reachedAtMs: end,
      );
      if (nowMs - end < 15000) {
        alarms.ringNow(title: _alarmTitle(sub), body: _alarmBody(lim.task!));
      } else {
        // It rang while the app was closed: keep the alarm only if the
        // notification is still ringing.
        _verifyPersistedAlarm();
      }
      pomodoroEvents.value =
          PomodoroEvent(++_eventSerial, '🎯 Target reached for ${sub?.name ?? 'your task'}!');
    }
    _safeHaptic(HapticFeedback.heavyImpact);
    _changed(sessionsChanged: true);
    _checkNewAchievements();
  }

  String _alarmTitle(Subject? s) => '🎯 Target reached: ${s?.emoji ?? ''} ${s?.name ?? 'Study'}';
  String _alarmBody(PlanTask t) =>
      'You finished ${formatDuration(t.targetMs)}. Tap Stop to silence the alarm.';

  int? _scheduledAt;

  void _syncAlarmSchedule({bool force = false}) {
    if (!_loaded && !force) return;
    final t = _data.activeTimer;
    int? want;
    ({int atMs, bool isTarget, PlanTask? task, String dayKey})? lim;
    if (t != null) {
      lim = _limitFor(t);
      if (lim.isTarget && lim.atMs > nowMs) want = lim.atMs;
    }
    if (!force && want == _scheduledAt) return;
    _scheduledAt = want;
    if (want == null) {
      if (_data.alarm == null) alarms.cancel();
    } else {
      alarms.schedule(DateTime.fromMillisecondsSinceEpoch(want),
          title: _alarmTitle(subjectById(t!.subjectId)), body: _alarmBody(lim!.task!));
    }
  }

  void _verifyPersistedAlarm() {
    final a = _data.alarm;
    if (a == null) return;
    alarms.isRinging().then((ringing) {
      if (!ringing && _data.alarm == a && nowMs - a.reachedAtMs >= 15000) {
        _data.alarm = null;
        _changed();
      }
    });
  }

  AlarmState? get alarm => _data.alarm;

  /// Silences the alarm (the "Stop" button).
  void stopAlarm() {
    if (_data.alarm == null) return;
    _data.alarm = null;
    _scheduledAt = null;
    alarms.cancel();
    _safeHaptic(HapticFeedback.mediumImpact);
    _changed();
  }

  /// Stops the alarm and gives the task [minutes] more, keeping it selected.
  bool extendAfterAlarm(int minutes) {
    final a = _data.alarm;
    stopAlarm();
    if (a == null) return false;
    final task = _data.plans[a.dayKey]?.taskById(a.taskId);
    if (task == null) return false;
    task.targetMs = math.min(maxTargetMs, task.targetMs + minutes * 60000);
    _data.selectedTaskId = task.id;
    _data.selectedTaskDay = a.dayKey;
    _changed();
    return true;
  }

  /// Adds [minutes] to a task's target (e.g. "+15 min" on a finished task).
  PlanResult extendTask(String dayKey, String taskId, int minutes) {
    final task = _data.plans[dayKey]?.taskById(taskId);
    if (task == null) return PlanResult.notFound;
    return updatePlanTaskTarget(
        dayKey, taskId, math.min(maxTargetMs, task.targetMs + minutes * 60000));
  }

  // ---------------------------------------------------------------- subjects
  Subject addSubject({
    required String name,
    required double targetHours,
    String? emoji,
    int? color,
    String category = '',
  }) {
    final i = subjects.length;
    final s = Subject(
      id: newId(),
      name: name,
      targetHours: targetHours,
      emoji: emoji ?? subjectEmojis[i % subjectEmojis.length],
      color: color ?? subjectPalette[i % subjectPalette.length],
      category: category,
    );
    _data.subjects.add(s);
    final f = settings.homeFilterIds;
    if (f != null) f.add(s.id);
    _changed(sessionsChanged: true);
    return s;
  }

  void updateSubject(String id, void Function(Subject s) mutate) {
    final s = subjectById(id);
    if (s == null) return;
    mutate(s);
    _changed(sessionsChanged: true);
  }

  void deleteSubject(String id) {
    if (activeTimer?.subjectId == id || pomodoro?.subjectId == id) {
      _data.activeTimer = null;
      _data.pomodoro = null;
    }
    _data.subjects.removeWhere((s) => s.id == id);
    _data.sessions.removeWhere((s) => s.subjectId == id);
    for (final plan in _data.plans.values) {
      plan.tasks.removeWhere((t) => t.subjectId == id);
    }
    if (_data.alarm?.subjectId == id) {
      _data.alarm = null;
      alarms.cancel();
    }
    _dropInvalidSelection();
    settings.homeFilterIds?.remove(id);
    _changed(sessionsChanged: true);
  }

  void reorderSubjects(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final s = _data.subjects.removeAt(oldIndex);
    _data.subjects.insert(newIndex, s);
    _changed();
  }

  void toggleHomeFilter(String id) {
    final f = settings.homeFilterIds ?? subjects.map((s) => s.id).toList();
    if (f.contains(id)) {
      f.remove(id);
    } else {
      f.add(id);
    }
    settings.homeFilterIds = f.length == subjects.length ? null : f;
    _changed();
  }

  // ---------------------------------------------------------------- chapters
  void addChapter(String subjectId, String name) {
    final s = subjectById(subjectId);
    if (s == null || name.trim().isEmpty) return;
    s.chapters.add(Chapter(id: newId(), name: name.trim()));
    _changed();
  }

  void updateChapter(String subjectId, String chapterId, void Function(Chapter c) mutate) {
    final c = subjectById(subjectId)?.chapterById(chapterId);
    if (c == null) return;
    mutate(c);
    _changed(sessionsChanged: true);
  }

  void reorderChapters(String subjectId, int oldIndex, int newIndex) {
    final s = subjectById(subjectId);
    if (s == null) return;
    if (newIndex > oldIndex) newIndex--;
    final c = s.chapters.removeAt(oldIndex);
    s.chapters.insert(newIndex, c);
    _changed();
  }

  /// Study time of a deleted chapter stays with its subject.
  void deleteChapter(String subjectId, String chapterId) {
    final s = subjectById(subjectId);
    if (s == null) return;
    final c = s.chapterById(chapterId);
    if (c == null) return;
    if (activeTimer?.chapterId == chapterId) _stopEverything();
    s.legacyMs += c.legacyMs;
    s.chapters.remove(c);
    for (final ses in sessions) {
      if (ses.chapterId == chapterId) ses.chapterId = null;
    }
    _changed(sessionsChanged: true);
  }

  // ---------------------------------------------------------------- sessions
  void addSession(StudySession s) {
    _data.sessions.add(s);
    _data.sessions.sort((a, b) => a.startMs.compareTo(b.startMs));
    _changed(sessionsChanged: true);
    _checkNewAchievements();
  }

  void deleteSession(String id) {
    _data.sessions.removeWhere((s) => s.id == id);
    _changed(sessionsChanged: true);
  }

  void replaceSession(StudySession updated) {
    final i = _data.sessions.indexWhere((s) => s.id == updated.id);
    if (i < 0) return;
    _data.sessions[i] = updated;
    _data.sessions.sort((a, b) => a.startMs.compareTo(b.startMs));
    _changed(sessionsChanged: true);
  }

  // ---------------------------------------------------------------- goals
  void setActiveGoal(String id) {
    settings.activeGoalId = id;
    _changed();
  }

  void addGoal(String label, int hours) {
    final g = LevelGoal(id: newId(), label: label, hours: hours);
    _data.goals.add(g);
    settings.activeGoalId = g.id;
    _changed();
  }

  void updateGoal(String id, String label, int hours) {
    for (final g in goals) {
      if (g.id == id) {
        g.label = label;
        g.hours = hours;
      }
    }
    _changed();
  }

  void deleteGoal(String id) {
    if (goals.length <= 1) return;
    _data.goals.removeWhere((g) => g.id == id);
    if (settings.activeGoalId == id) settings.activeGoalId = goals.first.id;
    _changed();
  }

  // ---------------------------------------------------------------- categories
  void addCategory(String name) {
    final n = name.trim();
    if (n.isEmpty || categories.contains(n)) return;
    _data.categories.add(n);
    _changed();
  }

  void renameCategory(String oldName, String newName) {
    final n = newName.trim();
    if (n.isEmpty || categories.contains(n)) return;
    final i = categories.indexOf(oldName);
    if (i >= 0) _data.categories[i] = n;
    for (final s in subjects) {
      if (s.category == oldName) s.category = n;
    }
    _changed();
  }

  void deleteCategory(String name) {
    _data.categories.remove(name);
    for (final s in subjects) {
      if (s.category == name) s.category = '';
    }
    _changed();
  }

  // ---------------------------------------------------------------- settings
  void updateSettings(void Function(AppSettings s) mutate) {
    mutate(settings);
    _changed(sessionsChanged: true);
  }

  void updateProfile(void Function(UserProfile p) mutate) {
    mutate(profile);
    _changed();
  }

  // ---------------------------------------------------------------- data
  Future<void> exportBackup() => _storage.exportBackup(_data);

  Future<AppData?> pickBackup() => _storage.pickBackup();

  void replaceAll(AppData data) {
    _data = data;
    _data.alarm = null;
    alarms.cancel();
    _scheduledAt = null;
    _dropInvalidSelection();
    if (_data.goals.isEmpty) _data.goals = AppData().goals;
    _validateRunningState();
    _invalidate();
    _syncAchievementsSilently();
    _changed(sessionsChanged: true);
  }

  void resetAll() => replaceAll(AppData());
}
