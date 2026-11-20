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

/// Result of trying to start a timer (the To-Do book gate).
enum StartGate { ok, noTaskSelected, wrongSubject, targetReached }

/// Result of editing the To-Do book.
enum PlanResult { ok, unknownSubject, invalidTarget, duplicateSubject, pastDay, notFound }

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
    _clearStaleSelection();
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
      _clearStaleSelection();
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
  void _recordSession(String subjectId, String? chapterId, int start, int end,
      {bool pomodoro = false, bool force = false}) {
    if (end - start < (force ? 1 : minSessionMs)) return;
    if (subjectById(subjectId) == null) return;
    _data.sessions.add(StudySession(
      id: newId(),
      subjectId: subjectId,
      chapterId: subjectById(subjectId)?.chapterById(chapterId) == null ? null : chapterId,
      startMs: start,
      endMs: end,
      pomodoro: pomodoro,
    ));
    _invalidate();
  }

  /// Whether a timer for [subjectId] may start right now. A timer can only
  /// run for the task picked from today's page of the To-Do book.
  StartGate canStart(String subjectId) {
    final sel = selectedTask;
    if (sel == null) return StartGate.noTaskSelected;
    if (sel.subjectId != subjectId) return StartGate.wrongSubject;
    if (isTaskDone(todayKey, sel)) return StartGate.targetReached;
    return StartGate.ok;
  }

  /// Starts (or switches) the stopwatch. Only one timer runs at a time.
  StartGate startTimer(String subjectId, [String? chapterId]) {
    final gate = canStart(subjectId);
    if (gate != StartGate.ok) return gate;
    _stopEverything();
    _data.activeTimer = ActiveTimer(subjectId: subjectId, chapterId: chapterId, startMs: nowMs);
    _safeHaptic(HapticFeedback.lightImpact);
    alarms.ensurePermissions();
    _changed(sessionsChanged: true);
    return StartGate.ok;
  }

  void stopTimer() {
    _stopEverything();
    _safeHaptic(HapticFeedback.lightImpact);
    _changed(sessionsChanged: true);
    _checkNewAchievements();
  }

  /// Stopping is always allowed; starting goes through [canStart].
  StartGate toggleTimer(String subjectId, [String? chapterId]) {
    final t = activeTimer;
    if (t != null && t.subjectId == subjectId && t.chapterId == chapterId && pomodoro == null) {
      stopTimer();
      return StartGate.ok;
    }
    return startTimer(subjectId, chapterId);
  }

  void _safeHaptic(Future<void> Function() f) {
    try {
      f().catchError((_) {});
    } catch (_) {}
  }

  void _stopEverything() {
    final t = _data.activeTimer;
    if (t != null) {
      _recordSession(t.subjectId, t.chapterId, t.startMs, nowMs, pomodoro: _data.pomodoro != null);
    }
    _data.activeTimer = null;
    _data.pomodoro = null;
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

  StartGate startPomodoro(String subjectId, [String? chapterId]) {
    final gate = canStart(subjectId);
    if (gate != StartGate.ok) return gate;
    _stopEverything();
    final now = nowMs;
    _data.pomodoro = PomodoroState(
        subjectId: subjectId, chapterId: chapterId, phase: PomodoroPhase.work, phaseStartMs: now);
    _data.activeTimer = ActiveTimer(subjectId: subjectId, chapterId: chapterId, startMs: now);
    _safeHaptic(HapticFeedback.mediumImpact);
    alarms.ensurePermissions();
    _changed(sessionsChanged: true);
    return StartGate.ok;
  }

  void pausePomodoro() {
    final p = pomodoro;
    if (p == null || p.isPaused) return;
    final remaining = pomodoroRemainingMs;
    final t = activeTimer;
    if (t != null) _recordSession(t.subjectId, t.chapterId, t.startMs, nowMs, pomodoro: true);
    _data.activeTimer = null;
    _data.pomodoro = p.copyWith(pausedRemainingMs: remaining);
    _changed(sessionsChanged: true);
  }

  void resumePomodoro() {
    final p = pomodoro;
    if (p == null || !p.isPaused) return;
    if (p.phase == PomodoroPhase.work && canStart(p.subjectId) != StartGate.ok) {
      stopTimer();
      return;
    }
    final now = nowMs;
    final start = now - (phaseLengthMs(p.phase) - p.pausedRemainingMs!);
    _data.pomodoro = p.copyWith(phaseStartMs: start, clearPaused: true);
    if (p.phase == PomodoroPhase.work) {
      _data.activeTimer = ActiveTimer(subjectId: p.subjectId, chapterId: p.chapterId, startMs: now);
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
          _recordSession(t.subjectId, t.chapterId, t.startMs, end, pomodoro: true);
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
          _data.activeTimer =
              ActiveTimer(subjectId: p.subjectId, chapterId: p.chapterId, startMs: phaseEnd);
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

  /// The task picked on today's page, if any.
  PlanTask? get selectedTask {
    if (_data.selectedTaskDay != todayKey) return null;
    return _data.plans[todayKey]?.taskById(_data.selectedTaskId);
  }

  int taskProgressMs(String dayKey, PlanTask t) => subjectDayMs(t.subjectId, dayKey);

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

  /// Adds a subject to a page of the book. Only existing subjects, one line
  /// per subject, and never on a page in the past.
  PlanResult addPlanTask(String dayKey, String subjectId, int targetMs) {
    if (isPastDay(dayKey)) return PlanResult.pastDay;
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
    if (isPastDay(dayKey)) return PlanResult.pastDay;
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
    if (isPastDay(dayKey)) return PlanResult.pastDay;
    final plan = _data.plans[dayKey];
    final task = plan?.taskById(taskId);
    if (plan == null || task == null) return PlanResult.notFound;
    final wasSelected = _data.selectedTaskId == taskId && _data.selectedTaskDay == dayKey;
    if (wasSelected) {
      if (activeTimer?.subjectId == task.subjectId || pomodoro?.subjectId == task.subjectId) {
        _stopEverything();
      }
      _data.selectedTaskId = null;
      _data.selectedTaskDay = null;
    }
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
    if (plan == null || isPastDay(dayKey)) return;
    if (newIndex > oldIndex) newIndex--;
    plan.tasks.insert(newIndex, plan.tasks.removeAt(oldIndex));
    _changed();
  }

  void setDayNote(String dayKey, String note) {
    _ensurePlan(dayKey).note = note;
    _changed();
  }

  void setDayMood(String dayKey, int? mood) {
    _ensurePlan(dayKey).mood = mood;
    _changed();
  }

  /// Unfinished tasks of [fromKey] that could be carried to [toKey].
  List<PlanTask> carryOverCandidates(String fromKey, String toKey) {
    final to = planFor(toKey);
    return planFor(fromKey)
        .tasks
        .where((t) =>
            subjectById(t.subjectId) != null &&
            !isTaskDone(fromKey, t) &&
            to.taskForSubject(t.subjectId) == null)
        .toList();
  }

  /// Copies unfinished tasks with their remaining time. Returns how many.
  int carryOverUnfinished(String fromKey, String toKey) {
    if (isPastDay(toKey)) return 0;
    var n = 0;
    for (final t in carryOverCandidates(fromKey, toKey)) {
      var remaining = taskRemainingMs(fromKey, t);
      remaining = ((remaining + 59999) ~/ 60000) * 60000; // round up to a minute
      if (addPlanTask(toKey, t.subjectId, remaining.clamp(minTargetMs, maxTargetMs)) == PlanResult.ok) n++;
    }
    return n;
  }

  /// Picks a task on today's page; from now on only its subject can be timed.
  StartGate selectTask(String taskId) {
    final task = _data.plans[todayKey]?.taskById(taskId);
    if (task == null) return StartGate.noTaskSelected;
    if (isTaskDone(todayKey, task)) return StartGate.targetReached;
    final runningSubject = activeTimer?.subjectId ?? pomodoro?.subjectId;
    if (runningSubject != null && runningSubject != task.subjectId) _stopEverything();
    _data.selectedTaskId = task.id;
    _data.selectedTaskDay = todayKey;
    _safeHaptic(HapticFeedback.selectionClick);
    _changed(sessionsChanged: true);
    return StartGate.ok;
  }

  void clearSelection() {
    final sel = selectedTask;
    if (sel != null &&
        (activeTimer?.subjectId == sel.subjectId || pomodoro?.subjectId == sel.subjectId)) {
      _stopEverything();
    }
    _data.selectedTaskId = null;
    _data.selectedTaskDay = null;
    _changed(sessionsChanged: true);
  }

  void _clearStaleSelection() {
    if (_data.selectedTaskDay != null && _data.selectedTaskDay != todayKey) {
      _data.selectedTaskId = null;
      _data.selectedTaskDay = null;
    }
  }

  void _dropInvalidSelection() {
    final day = _data.selectedTaskDay;
    if (day != null && _data.plans[day]?.taskById(_data.selectedTaskId) == null) {
      _data.selectedTaskId = null;
      _data.selectedTaskDay = null;
    }
  }

  // ---------------------------------------------------------------- limits & alarm
  /// When the running timer must stop: the task target or the end of the
  /// study day, whichever comes first.
  ({int atMs, bool isTarget, PlanTask? task, String dayKey}) _limitFor(ActiveTimer t) {
    final h = settings.dayStartHour;
    final startDay = dayKeyForMs(t.startMs, h);
    var at = dayStartMoment(addDays(startDay, 1), h).millisecondsSinceEpoch;
    PlanTask? task;
    if (_data.selectedTaskDay == startDay) {
      final sel = _data.plans[startDay]?.taskById(_data.selectedTaskId);
      if (sel != null && sel.subjectId == t.subjectId) {
        final before = snapshot.subjectDaily[t.subjectId]?[startDay] ?? 0;
        final int reach = t.startMs + math.max<int>(0, sel.targetMs - before);
        if (reach <= at) {
          at = reach;
          task = sel;
        }
      }
    }
    return (atMs: at, isTarget: task != null, task: task, dayKey: startDay);
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
    _recordSession(t.subjectId, t.chapterId, t.startMs, end,
        pomodoro: _data.pomodoro != null, force: true);
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
    } else {
      _data.selectedTaskId = null;
      _data.selectedTaskDay = null;
      pomodoroEvents.value = PomodoroEvent(
          ++_eventSerial, '📖 A new page has begun — pick today\'s task in your book.');
    }
    _safeHaptic(HapticFeedback.heavyImpact);
    _changed(sessionsChanged: true);
    _checkNewAchievements();
  }

  String _alarmTitle(Subject? s) => '🎯 Target reached: ${s?.emoji ?? ''} ${s?.name ?? 'Study'}';
  String _alarmBody(PlanTask t) =>
      'You finished ${formatDuration(t.targetMs)} today. Tap Stop to silence the alarm.';

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
  StartGate extendAfterAlarm(int minutes) {
    final a = _data.alarm;
    stopAlarm();
    if (a == null) return StartGate.noTaskSelected;
    final task = _data.plans[a.dayKey]?.taskById(a.taskId);
    if (task == null || a.dayKey != todayKey) return StartGate.noTaskSelected;
    task.targetMs = math.min(maxTargetMs, task.targetMs + minutes * 60000);
    _data.selectedTaskId = task.id;
    _data.selectedTaskDay = todayKey;
    _changed();
    return StartGate.ok;
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
