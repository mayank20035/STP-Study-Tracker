import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stp_v2/models/models.dart';
import 'package:stp_v2/services/alarm_service.dart';
import 'package:stp_v2/services/storage_service.dart';
import 'package:stp_v2/state/study_store.dart';

// ------------------------------------------------------------------ fakes

AppData _copy(AppData d) => AppData.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);

class FakeStorage extends StorageService {
  AppData data;
  FakeStorage([AppData? d]) : data = d ?? AppData();
  @override
  Future<AppData> load() async => _copy(data);
  @override
  Future<void> save(AppData d) async => data = _copy(d);
}

class FakeAlarms implements AlarmScheduler {
  DateTime? scheduledAt;
  int cancels = 0;
  int rings = 0;
  int permissionAsks = 0;
  bool ringing = false;

  @override
  Future<void> schedule(DateTime at, {required String title, required String body}) async => scheduledAt = at;
  @override
  Future<void> cancel() async {
    scheduledAt = null;
    ringing = false;
    cancels++;
  }

  @override
  Future<void> ringNow({required String title, required String body}) async {
    rings++;
    ringing = true;
  }

  @override
  Future<bool> isRinging() async => ringing;
  @override
  Future<void> ensurePermissions() async => permissionAsks++;
}

class Clock {
  int ms;
  Clock(DateTime t) : ms = t.millisecondsSinceEpoch;
  void advance(Duration d) => ms += d.inMilliseconds;
  void set(DateTime t) => ms = t.millisecondsSinceEpoch;
}

class Harness {
  final StudyStore store;
  final FakeAlarms alarms;
  final FakeStorage storage;
  final Clock clock;
  Harness(this.store, this.alarms, this.storage, this.clock);

  /// Simulates closing the app and opening it again later.
  Future<Harness> reopen({Duration after = Duration.zero, bool notificationRinging = false}) async {
    await store.flush();
    clock.advance(after);
    alarms.ringing = notificationRinging;
    final s = StudyStore(storage: storage, alarms: alarms, clock: () => clock.ms, enableTicker: false);
    await s.load();
    await Future<void>.delayed(Duration.zero); // let async alarm checks finish
    return Harness(s, alarms, storage, clock);
  }
}

const today = '2026-03-10';
const tomorrow = '2026-03-11';
const yesterday = '2026-03-09';
final nine = DateTime(2026, 3, 10, 9);

Future<Harness> makeHarness({DateTime? at, AppData? data}) async {
  final clock = Clock(at ?? nine);
  final alarms = FakeAlarms();
  final storage = FakeStorage(data);
  final store = StudyStore(storage: storage, alarms: alarms, clock: () => clock.ms, enableTicker: false);
  await store.load();
  return Harness(store, alarms, storage, clock);
}

const min = 60000;
const hour = 3600000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Harness h;
  late StudyStore store;
  late Subject physics;
  late Subject maths;

  setUp(() async {
    h = await makeHarness();
    store = h.store;
    physics = store.addSubject(name: 'Physics', targetHours: 100);
    maths = store.addSubject(name: 'Maths', targetHours: 100);
    physics.chapters.add(Chapter(id: 'kin', name: 'Kinematics'));
  });

  String addTask(Subject s, int targetMs, [String day = today]) {
    expect(store.addPlanTask(day, s.id, targetMs), PlanResult.ok);
    return store.planFor(day).taskForSubject(s.id)!.id;
  }

  bool pick(String id, [String day = today]) => store.selectTask(day, id);

  // ---------------------------------------------------------------- adding
  group('adding tasks to a page', () {
    test('valid task appears on the page', () {
      addTask(physics, 2 * hour);
      final plan = store.planFor(today);
      expect(plan.tasks, hasLength(1));
      expect(plan.tasks.single.targetMs, 2 * hour);
    });

    test('only existing subjects can be added', () {
      expect(store.addPlanTask(today, 'ghost', hour), PlanResult.unknownSubject);
      expect(store.planFor(today).tasks, isEmpty);
    });

    test('target must be between 1 minute and 24 hours', () {
      expect(store.addPlanTask(today, physics.id, 0), PlanResult.invalidTarget);
      expect(store.addPlanTask(today, physics.id, -5 * min), PlanResult.invalidTarget);
      expect(store.addPlanTask(today, physics.id, 30000), PlanResult.invalidTarget);
      expect(store.addPlanTask(today, physics.id, 24 * hour + 1), PlanResult.invalidTarget);
      expect(store.addPlanTask(today, physics.id, min), PlanResult.ok);
      expect(store.addPlanTask(today, maths.id, 24 * hour), PlanResult.ok);
    });

    test('a subject can appear only once per page', () {
      addTask(physics, hour);
      expect(store.addPlanTask(today, physics.id, 2 * hour), PlanResult.duplicateSubject);
      expect(store.planFor(today).tasks, hasLength(1));
    });

    test('past and future pages can both be planned and edited', () {
      final past = addTask(physics, hour, yesterday);
      expect(store.updatePlanTaskTarget(yesterday, past, 2 * hour), PlanResult.ok);
      expect(store.removePlanTask(yesterday, past), PlanResult.ok);
      final future = addTask(physics, hour, tomorrow);
      expect(store.updatePlanTaskTarget(tomorrow, future, 2 * hour), PlanResult.ok);
    });

    test('time studied earlier shows up when the task is added later', () {
      store.addSession(StudySession(
          id: 'y',
          subjectId: physics.id,
          startMs: DateTime(2026, 3, 9, 18).millisecondsSinceEpoch,
          endMs: DateTime(2026, 3, 9, 18, 45).millisecondsSinceEpoch,
          manual: true));
      final id = addTask(physics, hour, yesterday);
      expect(store.taskProgressMs(yesterday, store.planFor(yesterday).taskById(id)!), 45 * min);
    });

    test('unknown task ids report notFound', () {
      expect(store.updatePlanTaskTarget(today, 'nope', hour), PlanResult.notFound);
      expect(store.removePlanTask(today, 'nope'), PlanResult.notFound);
    });
  });

  // ---------------------------------------------------------------- free timers
  group('timers without a pick', () {
    test('any subject can be timed without picking a task', () {
      store.startTimer(physics.id);
      expect(store.activeTimer, isNotNull);
      expect(store.activeTimer!.isLinked, isFalse);
      expect(store.timerRemainingMs, isNull);
      expect(h.alarms.scheduledAt, isNull, reason: 'no target, no alarm');
      store.toggleTimer(physics.id);
      store.startPomodoro(maths.id);
      expect(store.pomodoro, isNotNull);
    });

    test('free time counts toward that day\'s task, even when added afterwards', () {
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 40));
      store.stopTimer();
      final id = addTask(physics, hour);
      expect(store.taskProgressMs(today, store.planFor(today).taskById(id)!), 40 * min);
    });

    test('a free timer keeps running past the 5 AM boundary', () async {
      final late = await makeHarness(at: DateTime(2026, 3, 10, 22));
      final s = late.store;
      final p = s.addSubject(name: 'P', targetHours: 10);
      s.startTimer(p.id);
      late.clock.set(DateTime(2026, 3, 11, 5, 30));
      s.tick();
      expect(s.activeTimer, isNotNull);
      s.stopTimer();
      expect(s.subjectDayMs(p.id, today), 7 * hour);
      expect(s.subjectDayMs(p.id, tomorrow), 30 * min);
    });

    test('stopping is always allowed', () {
      final id = addTask(physics, hour);
      pick(id);
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 5));
      store.toggleTimer(physics.id);
      expect(store.activeTimer, isNull);
      expect(store.sessions.single.durationMs, 5 * min);
    });

    test('starting a timer asks for alarm permissions', () {
      store.startTimer(physics.id);
      expect(h.alarms.permissionAsks, 1);
    });
  });

  // ---------------------------------------------------------------- picking
  group('picking a task', () {
    test('a pick links only its own subject\'s timer', () {
      final id = addTask(physics, hour);
      addTask(maths, hour);
      expect(pick(id), isTrue);
      store.startTimer(maths.id);
      expect(store.activeTimer!.isLinked, isFalse);
      expect(h.alarms.scheduledAt, isNull);
      store.startTimer(physics.id, 'kin');
      expect(store.activeTimer!.isLinked, isTrue);
      expect(store.activeTimer!.chapterId, 'kin');
      expect(store.linkedTask?.id, id);
      expect(h.alarms.scheduledAt, isNotNull);
    });

    test('future tasks can be picked and finished ahead of time', () {
      final todayTask = addTask(physics, hour);
      final future = addTask(physics, hour, tomorrow);
      expect(pick(future, tomorrow), isTrue);
      expect(store.selectedTaskDay, tomorrow);
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 20));
      store.stopTimer();
      final ses = store.sessions.single;
      expect(ses.planDay, tomorrow);
      expect(store.taskProgressMs(tomorrow, store.planFor(tomorrow).taskById(future)!), 20 * min);
      expect(store.taskProgressMs(today, store.planFor(today).taskById(todayTask)!), 0,
          reason: 'time for tomorrow does not count on today\'s page');
      expect(store.subjectTodayMs(physics.id), 20 * min, reason: 'it was still studied today');
    });

    test('a future task rings its alarm at the target', () {
      final future = addTask(physics, 30 * min, tomorrow);
      pick(future, tomorrow);
      store.startTimer(physics.id);
      expect(store.timerRemainingMs, 30 * min);
      h.clock.advance(const Duration(minutes: 31));
      store.tick();
      expect(store.activeTimer, isNull);
      expect(store.alarm?.dayKey, tomorrow);
      expect(store.isTaskDone(tomorrow, store.planFor(tomorrow).taskById(future)!), isTrue);
    });

    test('a missed task can be picked and finished later', () {
      final missed = addTask(physics, 30 * min, yesterday);
      final todayTask = addTask(physics, hour);
      expect(store.pageStatus(yesterday), PageStatus.missed);
      expect(pick(missed, yesterday), isTrue);
      expect(store.selectedTaskDay, yesterday);
      store.startTimer(physics.id);
      expect(store.timerRemainingMs, 30 * min);
      h.clock.advance(const Duration(minutes: 31));
      store.tick();
      expect(store.activeTimer, isNull, reason: 'stops at the target');
      expect(store.alarm?.dayKey, yesterday);
      expect(store.sessions.single.planDay, yesterday);
      expect(store.isTaskDone(yesterday, store.planFor(yesterday).taskById(missed)!), isTrue);
      expect(store.pageStatus(yesterday), PageStatus.conquered);
      expect(store.taskProgressMs(today, store.planFor(today).taskById(todayTask)!), 0,
          reason: 'catch-up time counts on the missed page, not today');
      expect(store.subjectTodayMs(physics.id), 30 * min, reason: 'it was still studied today');
      expect(store.extendAfterAlarm(15), isTrue, reason: '+15 min works for a missed page too');
    });

    test('finished and unknown tasks cannot be picked', () {
      expect(pick('missing'), isFalse);
      final id = addTask(maths, 30 * min);
      store.addSession(StudySession(
          id: 'm',
          subjectId: maths.id,
          startMs: nine.millisecondsSinceEpoch - hour,
          endMs: nine.millisecondsSinceEpoch,
          manual: true));
      expect(pick(id), isFalse);
      expect(store.selectedTask, isNull);
    });

    test('picking another subject\'s task stops a linked timer and saves it', () {
      final a = addTask(physics, hour);
      final b = addTask(maths, hour);
      pick(a);
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 12));
      expect(pick(b), isTrue);
      expect(store.activeTimer, isNull);
      expect(store.sessions.single.durationMs, 12 * min);
    });

    test('picking a task while a free timer of its subject runs links it from now on', () {
      final id = addTask(physics, hour);
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 10));
      pick(id);
      expect(store.activeTimer!.isLinked, isTrue);
      expect(store.sessions.single.durationMs, 10 * min);
      expect(store.timerRemainingMs, 50 * min);
    });

    test('picking a task leaves a free timer of another subject running', () {
      final id = addTask(physics, hour);
      store.startTimer(maths.id);
      pick(id);
      expect(store.activeTimer?.subjectId, maths.id);
      expect(store.activeTimer!.isLinked, isFalse);
    });

    test('unpicking keeps the timer running as a free timer', () {
      final a = addTask(physics, hour);
      pick(a);
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 3));
      store.clearSelection();
      expect(store.activeTimer, isNotNull);
      expect(store.activeTimer!.isLinked, isFalse);
      expect(store.sessions.single.durationMs, 3 * min);
      expect(h.alarms.scheduledAt, isNull);
    });
  });

  // ---------------------------------------------------------------- auto stop
  group('auto-stop when the target is reached', () {
    test('stops exactly at the target and rings the alarm', () {
      final id = addTask(physics, hour);
      pick(id);
      store.startTimer(physics.id);
      final start = h.clock.ms;
      expect(h.alarms.scheduledAt, DateTime.fromMillisecondsSinceEpoch(start + hour));

      h.clock.advance(const Duration(minutes: 30));
      store.tick();
      expect(store.activeTimer, isNotNull);
      expect(store.timerRemainingMs, 30 * min);

      h.clock.advance(const Duration(minutes: 30, seconds: 1));
      store.tick();
      expect(store.activeTimer, isNull);
      expect(store.sessions.single.endMs, start + hour, reason: 'no overshoot');
      expect(store.alarm, isNotNull);
      expect(store.alarm!.taskId, id);
      expect(h.alarms.rings, 1);
      expect(store.isTaskDone(today, store.selectedTask!), isTrue);

      // Studying more after the target is allowed, as a free timer.
      store.startTimer(physics.id);
      expect(store.activeTimer!.isLinked, isFalse);
      expect(store.timerRemainingMs, isNull);
    });

    test('earlier and manual sessions of the day count towards the target', () {
      final id = addTask(physics, hour);
      store.addSession(StudySession(
          id: 'm',
          subjectId: physics.id,
          startMs: DateTime(2026, 3, 10, 6).millisecondsSinceEpoch,
          endMs: DateTime(2026, 3, 10, 6, 40).millisecondsSinceEpoch,
          manual: true));
      pick(id);
      store.startTimer(physics.id);
      expect(store.timerRemainingMs, 20 * min);
      h.clock.advance(const Duration(minutes: 20));
      store.tick();
      expect(store.activeTimer, isNull);
      expect(store.taskProgressMs(today, store.selectedTask!), hour);
    });

    test('yesterday\'s study does not count for today', () {
      final id = addTask(physics, hour);
      store.addSession(StudySession(
          id: 'y',
          subjectId: physics.id,
          startMs: DateTime(2026, 3, 9, 20).millisecondsSinceEpoch,
          endMs: DateTime(2026, 3, 9, 22).millisecondsSinceEpoch,
          manual: true));
      expect(pick(id), isTrue);
      expect(store.taskProgressMs(today, store.selectedTask!), 0);
    });

    test('a manual stop cancels the scheduled alarm', () {
      final id = addTask(physics, hour);
      pick(id);
      store.startTimer(physics.id);
      expect(h.alarms.scheduledAt, isNotNull);
      h.clock.advance(const Duration(minutes: 10));
      store.stopTimer();
      expect(h.alarms.scheduledAt, isNull);
      expect(store.alarm, isNull);
    });

    test('restarting reschedules the alarm for the remaining time', () {
      final id = addTask(physics, hour);
      pick(id);
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 40));
      store.stopTimer();
      h.clock.advance(const Duration(minutes: 5));
      store.startTimer(physics.id);
      expect(h.alarms.scheduledAt, DateTime.fromMillisecondsSinceEpoch(h.clock.ms + 20 * min));
    });

    test('app closed past the target: session trimmed, alarm kept while notification rings', () async {
      final id = addTask(physics, hour);
      pick(id);
      store.startTimer(physics.id);
      final start = h.clock.ms;
      final h2 = await h.reopen(after: const Duration(hours: 3), notificationRinging: true);
      expect(h2.store.activeTimer, isNull);
      expect(h2.store.sessions.single.endMs, start + hour);
      expect(h2.store.alarm, isNotNull);
      expect(h2.alarms.rings, 0, reason: 'the scheduled notification already rang');
      expect(h2.store.selectedTask?.id, id);
    });

    test('app closed past the target and alarm already stopped from the notification', () async {
      final id = addTask(physics, hour);
      pick(id);
      store.startTimer(physics.id);
      final h2 = await h.reopen(after: const Duration(hours: 2), notificationRinging: false);
      expect(h2.store.activeTimer, isNull);
      expect(h2.store.alarm, isNull);
      expect(h2.store.taskProgressMs(today, h2.store.selectedTask!), hour);
    });

    test('a timer still below target keeps running after reopening', () async {
      final id = addTask(physics, 2 * hour);
      pick(id);
      store.startTimer(physics.id);
      final h2 = await h.reopen(after: const Duration(minutes: 30));
      expect(h2.store.activeTimer, isNotNull);
      expect(h2.store.activeTimer!.isLinked, isTrue);
      expect(h2.store.timerRemainingMs, 90 * min);
      expect(h2.alarms.scheduledAt, DateTime.fromMillisecondsSinceEpoch(h2.clock.ms + 90 * min));
    });

    test('a linked timer for a future page survives reopening', () async {
      final future = addTask(physics, hour, tomorrow);
      pick(future, tomorrow);
      store.startTimer(physics.id);
      final h2 = await h.reopen(after: const Duration(minutes: 15));
      expect(h2.store.timerRemainingMs, 45 * min);
      h2.store.stopTimer();
      expect(h2.store.sessions.single.planDay, tomorrow);
    });
  });

  // ---------------------------------------------------------------- edits
  group('editing while a timer runs', () {
    test('lowering the target below progress stops now and rings, keeping real time', () {
      final id = addTask(physics, 2 * hour);
      pick(id);
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 50));
      expect(store.updatePlanTaskTarget(today, id, 30 * min), PlanResult.ok);
      expect(store.activeTimer, isNull);
      expect(store.sessions.single.durationMs, 50 * min);
      expect(store.alarm, isNotNull);
    });

    test('raising the target keeps it running and moves the alarm', () {
      final id = addTask(physics, hour);
      pick(id);
      store.startTimer(physics.id);
      final start = h.clock.ms;
      h.clock.advance(const Duration(minutes: 30));
      store.updatePlanTaskTarget(today, id, 2 * hour);
      expect(store.activeTimer, isNotNull);
      expect(h.alarms.scheduledAt, DateTime.fromMillisecondsSinceEpoch(start + 2 * hour));
    });

    test('invalid edit is refused and changes nothing', () {
      final id = addTask(physics, hour);
      expect(store.updatePlanTaskTarget(today, id, 0), PlanResult.invalidTarget);
      expect(store.planFor(today).taskById(id)!.targetMs, hour);
    });

    test('removing the running task keeps timing freely and clears the pick', () {
      final id = addTask(physics, hour);
      pick(id);
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 15));
      expect(store.removePlanTask(today, id), PlanResult.ok);
      expect(store.activeTimer, isNotNull);
      expect(store.activeTimer!.isLinked, isFalse);
      expect(store.sessions.single.durationMs, 15 * min);
      expect(store.selectedTask, isNull);
      expect(h.alarms.scheduledAt, isNull);
    });

    test('deleting a subject removes its tasks from every page and the pick', () {
      final id = addTask(physics, hour);
      addTask(physics, hour, tomorrow);
      addTask(maths, hour);
      pick(id);
      store.deleteSubject(physics.id);
      expect(store.planFor(today).tasks.map((t) => t.subjectId), [maths.id]);
      expect(store.planFor(tomorrow).tasks, isEmpty);
      expect(store.selectedTask, isNull);
    });
  });

  // ---------------------------------------------------------------- alarm
  group('alarm', () {
    Future<String> reachTarget() async {
      final id = addTask(physics, 30 * min);
      pick(id);
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 30));
      store.tick();
      return id;
    }

    test('Stop silences it', () async {
      await reachTarget();
      expect(h.alarms.ringing, isTrue);
      store.stopAlarm();
      expect(store.alarm, isNull);
      expect(h.alarms.ringing, isFalse);
    });

    test('+15 min stops the alarm and lets the task continue', () async {
      final id = await reachTarget();
      expect(store.extendAfterAlarm(15), isTrue);
      expect(store.alarm, isNull);
      expect(store.planFor(today).taskById(id)!.targetMs, 45 * min);
      store.startTimer(physics.id);
      expect(store.timerRemainingMs, 15 * min);
    });

    test('extending a finished task from the book re-opens it', () async {
      final id = await reachTarget();
      store.stopAlarm();
      expect(store.extendTask(today, id, 30), PlanResult.ok);
      store.startTimer(physics.id);
      expect(store.activeTimer!.isLinked, isTrue);
      expect(store.timerRemainingMs, 30 * min);
    });

    test('the ringing alarm survives an app restart', () async {
      await reachTarget();
      final h2 = await h.reopen(after: const Duration(seconds: 30), notificationRinging: true);
      expect(h2.store.alarm, isNotNull);
      h2.store.stopAlarm();
      expect(h2.store.alarm, isNull);
    });
  });

  // ---------------------------------------------------------------- pomodoro
  group('pomodoro with a target', () {
    test('break time does not count and the target ends the pomodoro', () {
      final id = addTask(physics, 30 * min);
      pick(id);
      store.startPomodoro(physics.id);
      h.clock.advance(const Duration(minutes: 25));
      store.tick(); // focus block done -> short break
      expect(store.pomodoro!.phase, PomodoroPhase.shortBreak);
      expect(store.activeTimer, isNull);
      h.clock.advance(const Duration(minutes: 5));
      store.tick(); // break over -> next focus block auto-starts, still linked
      expect(store.pomodoro!.phase, PomodoroPhase.work);
      expect(store.activeTimer!.isLinked, isTrue);
      h.clock.advance(const Duration(minutes: 6));
      store.tick();
      expect(store.pomodoro, isNull);
      expect(store.activeTimer, isNull);
      expect(store.alarm, isNotNull);
      expect(store.taskProgressMs(today, store.selectedTask!), 30 * min);
      expect(store.sessions.map((s) => s.durationMs), [25 * min, 5 * min]);
    });

    test('target inside the first focus block ends it early', () {
      final id = addTask(physics, 10 * min);
      pick(id);
      store.startPomodoro(physics.id);
      h.clock.advance(const Duration(minutes: 11));
      store.tick();
      expect(store.pomodoro, isNull);
      expect(store.sessions.single.durationMs, 10 * min);
    });

    test('a pomodoro without a pick runs freely', () {
      store.startPomodoro(physics.id);
      h.clock.advance(const Duration(minutes: 25));
      store.tick();
      expect(store.pomodoro!.phase, PomodoroPhase.shortBreak);
      expect(store.sessions.single.durationMs, 25 * min);
      expect(store.alarm, isNull);
    });

    test('closed during a pomodoro past the target', () async {
      final id = addTask(physics, 40 * min);
      pick(id);
      store.startPomodoro(physics.id);
      final h2 = await h.reopen(after: const Duration(hours: 2), notificationRinging: true);
      expect(h2.store.pomodoro, isNull);
      expect(h2.store.taskProgressMs(today, h2.store.selectedTask!), 40 * min);
    });
  });

  // ---------------------------------------------------------------- day change
  group('new day', () {
    test('a linked timer keeps counting toward its page past 5 AM', () async {
      final late = await makeHarness(at: DateTime(2026, 3, 10, 22));
      final s = late.store;
      final p = s.addSubject(name: 'P', targetHours: 10);
      expect(s.addPlanTask(today, p.id, 10 * hour), PlanResult.ok);
      s.selectTask(today, s.planFor(today).tasks.single.id);
      s.startTimer(p.id);
      late.clock.set(DateTime(2026, 3, 11, 5, 30));
      s.tick();
      expect(s.activeTimer, isNotNull);
      expect(s.timerRemainingMs, 2 * hour + 30 * min);
      s.stopTimer();
      expect(s.taskProgressMs(today, s.planFor(today).tasks.single), 7 * hour + 30 * min);
      expect(s.selectedTask?.id, s.planFor(today).tasks.single.id, reason: 'the pick stays');
      expect(s.alarm, isNull);
    });

    test('after midnight but before 5 AM it is still the same page', () async {
      final late = await makeHarness(at: DateTime(2026, 3, 11, 1));
      expect(late.store.todayKey, today);
    });

    test('a pick from yesterday stays, so the missed task can still be finished', () async {
      final id = addTask(physics, hour);
      pick(id);
      final h2 = await h.reopen(after: const Duration(days: 1));
      expect(h2.store.selectedTask?.id, id);
      expect(h2.store.selectedTaskDay, today);
      h2.store.startTimer(physics.id);
      expect(h2.store.timerRemainingMs, hour);
    });

    test('a pick on a future page is kept when that day arrives', () async {
      final future = addTask(physics, hour, tomorrow);
      pick(future, tomorrow);
      final h2 = await h.reopen(after: const Duration(days: 1));
      expect(h2.store.todayKey, tomorrow);
      expect(h2.store.selectedTask?.id, future);
    });
  });

  // ---------------------------------------------------------------- pages
  group('pages', () {
    AppData pastData() {
      final d = AppData(subjects: [
        Subject(id: 'a', name: 'A'),
        Subject(id: 'b', name: 'B'),
      ], sessions: [
        StudySession(
            id: '1',
            subjectId: 'a',
            startMs: DateTime(2026, 3, 9, 10).millisecondsSinceEpoch,
            endMs: DateTime(2026, 3, 9, 10, 20).millisecondsSinceEpoch),
        StudySession(
            id: '2',
            subjectId: 'b',
            startMs: DateTime(2026, 3, 9, 11).millisecondsSinceEpoch,
            endMs: DateTime(2026, 3, 9, 11, 30).millisecondsSinceEpoch),
      ]);
      d.plans[yesterday] = DayPlan(dayKey: yesterday, tasks: [
        PlanTask(id: 'ta', subjectId: 'a', targetMs: hour),
        PlanTask(id: 'tb', subjectId: 'b', targetMs: 30 * min),
      ]);
      return d;
    }

    test('page status and score', () async {
      final p = await makeHarness(data: pastData());
      final s = p.store;
      expect(s.pageStatus(yesterday), PageStatus.partial);
      final score = s.pageScore(yesterday);
      expect(score.done, 1);
      expect(score.total, 2);
      expect(score.percent, closeTo((20 + 30) / 90, 1e-9));
      s.data.plans['2026-03-08'] =
          DayPlan(dayKey: '2026-03-08', tasks: [PlanTask(id: 'x', subjectId: 'a', targetMs: hour)]);
      expect(s.pageStatus('2026-03-08'), PageStatus.missed);
      s.data.plans['2026-03-07'] =
          DayPlan(dayKey: '2026-03-07', tasks: [PlanTask(id: 'y', subjectId: 'b', targetMs: 10 * min)]);
      s.addSession(StudySession(
          id: 'z',
          subjectId: 'b',
          startMs: DateTime(2026, 3, 7, 10).millisecondsSinceEpoch,
          endMs: DateTime(2026, 3, 7, 10, 15).millisecondsSinceEpoch));
      expect(s.pageStatus('2026-03-07'), PageStatus.conquered);
      expect(s.pageStatus(tomorrow), PageStatus.upcoming);
      expect(s.pageStatus(today), PageStatus.today);
      expect(s.pageStatus('2026-03-01'), PageStatus.empty);
    });

    test('notes and mood are saved per page', () async {
      store.setDayNote(today, 'Great focus today');
      store.setDayMood(today, 4);
      final h2 = await h.reopen();
      expect(h2.store.planFor(today).note, 'Great focus today');
      expect(h2.store.planFor(today).mood, 4);
    });

    test('reordering tasks', () {
      addTask(physics, hour);
      addTask(maths, hour);
      store.reorderPlanTasks(today, 1, 0);
      expect(store.planFor(today).tasks.first.subjectId, maths.id);
    });
  });

  // ---------------------------------------------------------------- persistence
  group('persistence', () {
    test('plans and the pick round-trip through JSON', () async {
      final id = addTask(physics, 90 * min);
      addTask(maths, hour, tomorrow);
      pick(id);
      final h2 = await h.reopen();
      expect(h2.store.planFor(today).tasks.single.targetMs, 90 * min);
      expect(h2.store.planFor(tomorrow).tasks, hasLength(1));
      expect(h2.store.selectedTask?.id, id);
    });

    test('the last open book page is remembered', () async {
      expect(store.bookPage, isNull);
      store.rememberBookPage('2026-03-14');
      final h2 = await h.reopen();
      expect(h2.store.bookPage, '2026-03-14');
    });

    test('older backups without a book still load', () {
      final json = AppData().toJson()
        ..remove('plans')
        ..remove('selectedTaskId')
        ..remove('alarm')
        ..remove('bookPage');
      final d = AppData.fromJson(json);
      expect(d.plans, isEmpty);
      expect(d.alarm, isNull);
      expect(d.bookPage, isNull);
    });

    test('a session\'s page tag round-trips and is omitted when unset', () {
      final s = StudySession(id: '1', subjectId: 'a', startMs: 0, endMs: 1, planDay: tomorrow);
      expect(StudySession.fromJson(s.toJson()).planDay, tomorrow);
      expect(StudySession(id: '2', subjectId: 'a', startMs: 0, endMs: 1).toJson().containsKey('d'), isFalse);
    });

    test('empty pages are not written to storage', () {
      store.planFor(tomorrow); // just looking at a page
      expect(store.data.toJson()['plans'], isEmpty);
    });

    test('importing a backup clears a ringing alarm and a stale pick', () {
      final id = addTask(physics, 10 * min);
      pick(id);
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 10));
      store.tick();
      expect(store.alarm, isNotNull);
      store.replaceAll(AppData());
      expect(store.alarm, isNull);
      expect(store.selectedTask, isNull);
    });
  });
}
