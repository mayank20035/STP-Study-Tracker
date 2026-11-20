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

    test('past pages are read-only, future pages can be planned', () {
      expect(store.addPlanTask(yesterday, physics.id, hour), PlanResult.pastDay);
      expect(store.addPlanTask(tomorrow, physics.id, hour), PlanResult.ok);
      final id = store.planFor(tomorrow).tasks.single.id;
      expect(store.updatePlanTaskTarget(tomorrow, id, 2 * hour), PlanResult.ok);
    });

    test('editing or removing a past task is refused', () {
      final data = h.storage.data;
      data.subjects.addAll(store.subjects);
      store.data.plans[yesterday] =
          DayPlan(dayKey: yesterday, tasks: [PlanTask(id: 'old', subjectId: physics.id, targetMs: hour)]);
      expect(store.updatePlanTaskTarget(yesterday, 'old', 2 * hour), PlanResult.pastDay);
      expect(store.removePlanTask(yesterday, 'old'), PlanResult.pastDay);
      expect(store.planFor(yesterday).tasks, hasLength(1));
    });

    test('unknown task ids report notFound', () {
      expect(store.updatePlanTaskTarget(today, 'nope', hour), PlanResult.notFound);
      expect(store.removePlanTask(today, 'nope'), PlanResult.notFound);
    });
  });

  // ---------------------------------------------------------------- gate
  group('timer gate', () {
    test('no timer can start without picking a task', () {
      expect(store.startTimer(physics.id), StartGate.noTaskSelected);
      expect(store.startPomodoro(physics.id), StartGate.noTaskSelected);
      expect(store.toggleTimer(physics.id), StartGate.noTaskSelected);
      expect(store.activeTimer, isNull);
    });

    test('only the picked subject can be timed (any chapter)', () {
      final id = addTask(physics, hour);
      addTask(maths, hour);
      expect(store.selectTask(id), StartGate.ok);
      expect(store.startTimer(maths.id), StartGate.wrongSubject);
      expect(store.activeTimer, isNull);
      expect(store.startTimer(physics.id, 'kin'), StartGate.ok);
      expect(store.activeTimer!.chapterId, 'kin');
      expect(store.startTimer(physics.id), StartGate.ok, reason: 'switching chapter within subject');
      expect(store.activeTimer!.chapterId, isNull);
    });

    test('stopping is always allowed', () {
      final id = addTask(physics, hour);
      store.selectTask(id);
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 5));
      expect(store.toggleTimer(physics.id), StartGate.ok);
      expect(store.activeTimer, isNull);
      expect(store.sessions.single.durationMs, 5 * min);
    });

    test('starting a timer asks for alarm permissions', () {
      final id = addTask(physics, hour);
      store.selectTask(id);
      store.startTimer(physics.id);
      expect(h.alarms.permissionAsks, 1);
    });

    test('tasks can only be picked from today\'s page', () {
      final future = addTask(physics, hour, tomorrow);
      expect(store.selectTask(future), StartGate.noTaskSelected);
      expect(store.selectTask('missing'), StartGate.noTaskSelected);
      expect(store.selectedTask, isNull);
    });

    test('a finished task cannot be picked or started', () {
      final id = addTask(physics, 30 * min);
      store.addSession(StudySession(
          id: 'm', subjectId: physics.id, startMs: nine.millisecondsSinceEpoch - hour, endMs: nine.millisecondsSinceEpoch, manual: true));
      expect(store.selectTask(id), StartGate.targetReached);
    });

    test('switching task stops the other subject\'s timer and saves it', () {
      final a = addTask(physics, hour);
      final b = addTask(maths, hour);
      store.selectTask(a);
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 12));
      expect(store.selectTask(b), StartGate.ok);
      expect(store.activeTimer, isNull);
      expect(store.sessions.single.subjectId, physics.id);
      expect(store.sessions.single.durationMs, 12 * min);
      expect(store.canStart(maths.id), StartGate.ok);
      expect(store.canStart(physics.id), StartGate.wrongSubject);
    });

    test('clearing the selection stops its timer', () {
      final a = addTask(physics, hour);
      store.selectTask(a);
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 3));
      store.clearSelection();
      expect(store.activeTimer, isNull);
      expect(store.canStart(physics.id), StartGate.noTaskSelected);
    });
  });

  // ---------------------------------------------------------------- auto stop
  group('auto-stop when the target is reached', () {
    test('stops exactly at the target and rings the alarm', () {
      final id = addTask(physics, hour);
      store.selectTask(id);
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
      expect(store.canStart(physics.id), StartGate.targetReached);
      expect(store.startTimer(physics.id), StartGate.targetReached);
    });

    test('earlier and manual sessions of the day count towards the target', () {
      final id = addTask(physics, hour);
      store.addSession(StudySession(
          id: 'm',
          subjectId: physics.id,
          startMs: DateTime(2026, 3, 10, 6).millisecondsSinceEpoch,
          endMs: DateTime(2026, 3, 10, 6, 40).millisecondsSinceEpoch,
          manual: true));
      store.selectTask(id);
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
      expect(store.selectTask(id), StartGate.ok);
      expect(store.taskProgressMs(today, store.selectedTask!), 0);
    });

    test('a manual stop cancels the scheduled alarm', () {
      final id = addTask(physics, hour);
      store.selectTask(id);
      store.startTimer(physics.id);
      expect(h.alarms.scheduledAt, isNotNull);
      h.clock.advance(const Duration(minutes: 10));
      store.stopTimer();
      expect(h.alarms.scheduledAt, isNull);
      expect(store.alarm, isNull);
      expect(store.canStart(physics.id), StartGate.ok);
    });

    test('restarting reschedules the alarm for the remaining time', () {
      final id = addTask(physics, hour);
      store.selectTask(id);
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 40));
      store.stopTimer();
      h.clock.advance(const Duration(minutes: 5));
      store.startTimer(physics.id);
      expect(h.alarms.scheduledAt, DateTime.fromMillisecondsSinceEpoch(h.clock.ms + 20 * min));
    });

    test('app closed past the target: session trimmed, alarm kept while notification rings', () async {
      final id = addTask(physics, hour);
      store.selectTask(id);
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
      store.selectTask(id);
      store.startTimer(physics.id);
      final h2 = await h.reopen(after: const Duration(hours: 2), notificationRinging: false);
      expect(h2.store.activeTimer, isNull);
      expect(h2.store.alarm, isNull);
      expect(h2.store.taskProgressMs(today, h2.store.selectedTask!), hour);
    });

    test('a timer still below target keeps running after reopening', () async {
      final id = addTask(physics, 2 * hour);
      store.selectTask(id);
      store.startTimer(physics.id);
      final h2 = await h.reopen(after: const Duration(minutes: 30));
      expect(h2.store.activeTimer, isNotNull);
      expect(h2.store.timerRemainingMs, 90 * min);
      expect(h2.alarms.scheduledAt, DateTime.fromMillisecondsSinceEpoch(h2.clock.ms + 90 * min));
    });
  });

  // ---------------------------------------------------------------- edits
  group('editing while a timer runs', () {
    test('lowering the target below progress stops now and rings, keeping real time', () {
      final id = addTask(physics, 2 * hour);
      store.selectTask(id);
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 50));
      expect(store.updatePlanTaskTarget(today, id, 30 * min), PlanResult.ok);
      expect(store.activeTimer, isNull);
      expect(store.sessions.single.durationMs, 50 * min);
      expect(store.alarm, isNotNull);
    });

    test('raising the target keeps it running and moves the alarm', () {
      final id = addTask(physics, hour);
      store.selectTask(id);
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

    test('removing the running task stops it, saves the time and clears the pick', () {
      final id = addTask(physics, hour);
      store.selectTask(id);
      store.startTimer(physics.id);
      h.clock.advance(const Duration(minutes: 15));
      expect(store.removePlanTask(today, id), PlanResult.ok);
      expect(store.activeTimer, isNull);
      expect(store.sessions.single.durationMs, 15 * min);
      expect(store.selectedTask, isNull);
      expect(h.alarms.scheduledAt, isNull);
    });

    test('deleting a subject removes its tasks from every page and the pick', () {
      final id = addTask(physics, hour);
      addTask(physics, hour, tomorrow);
      addTask(maths, hour);
      store.selectTask(id);
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
      store.selectTask(id);
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
      expect(store.extendAfterAlarm(15), StartGate.ok);
      expect(store.alarm, isNull);
      expect(store.planFor(today).taskById(id)!.targetMs, 45 * min);
      expect(store.startTimer(physics.id), StartGate.ok);
      expect(store.timerRemainingMs, 15 * min);
    });

    test('extending a finished task from the book re-opens it', () async {
      final id = await reachTarget();
      store.stopAlarm();
      expect(store.extendTask(today, id, 30), PlanResult.ok);
      expect(store.canStart(physics.id), StartGate.ok);
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
      store.selectTask(id);
      expect(store.startPomodoro(physics.id), StartGate.ok);
      h.clock.advance(const Duration(minutes: 25));
      store.tick(); // focus block done -> short break
      expect(store.pomodoro!.phase, PomodoroPhase.shortBreak);
      expect(store.activeTimer, isNull);
      h.clock.advance(const Duration(minutes: 5));
      store.tick(); // break over -> next focus block auto-starts
      expect(store.pomodoro!.phase, PomodoroPhase.work);
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
      store.selectTask(id);
      store.startPomodoro(physics.id);
      h.clock.advance(const Duration(minutes: 11));
      store.tick();
      expect(store.pomodoro, isNull);
      expect(store.sessions.single.durationMs, 10 * min);
    });

    test('closed during a pomodoro past the target', () async {
      final id = addTask(physics, 40 * min);
      store.selectTask(id);
      store.startPomodoro(physics.id);
      final h2 = await h.reopen(after: const Duration(hours: 2), notificationRinging: true);
      expect(h2.store.pomodoro, isNull);
      expect(h2.store.taskProgressMs(today, h2.store.selectedTask!), 40 * min);
    });
  });

  // ---------------------------------------------------------------- day change
  group('new day', () {
    test('timer stops at the 5 AM boundary and the pick is cleared', () async {
      final late = await makeHarness(at: DateTime(2026, 3, 10, 22));
      final s = late.store;
      final p = s.addSubject(name: 'P', targetHours: 10);
      expect(s.addPlanTask(today, p.id, 10 * hour), PlanResult.ok);
      s.selectTask(s.planFor(today).tasks.single.id);
      s.startTimer(p.id);
      late.clock.set(DateTime(2026, 3, 11, 5, 30));
      s.tick();
      expect(s.activeTimer, isNull);
      expect(s.sessions.single.endMs, DateTime(2026, 3, 11, 5).millisecondsSinceEpoch);
      expect(s.taskProgressMs(today, s.planFor(today).tasks.single), 7 * hour);
      expect(s.selectedTask, isNull);
      expect(s.alarm, isNull);
      expect(s.canStart(p.id), StartGate.noTaskSelected);
    });

    test('after midnight but before 5 AM it is still the same page', () async {
      final late = await makeHarness(at: DateTime(2026, 3, 11, 1));
      expect(late.store.todayKey, today);
    });

    test('a selection from yesterday is dropped on reopen', () async {
      final id = addTask(physics, hour);
      store.selectTask(id);
      final h2 = await h.reopen(after: const Duration(days: 1));
      expect(h2.store.selectedTask, isNull);
      expect(h2.store.canStart(physics.id), StartGate.noTaskSelected);
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

    test('carry over copies only unfinished tasks with the remaining time', () async {
      final p = await makeHarness(data: pastData());
      expect(p.store.carryOverCandidates(yesterday, today).map((t) => t.id), ['ta']);
      expect(p.store.carryOverUnfinished(yesterday, today), 1);
      final t = p.store.planFor(today).tasks.single;
      expect(t.subjectId, 'a');
      expect(t.targetMs, 40 * min);
      expect(p.store.carryOverUnfinished(yesterday, today), 0, reason: 'no duplicates');
      expect(p.store.carryOverUnfinished(today, yesterday), 0, reason: 'cannot write the past');
    });

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
      store.selectTask(id);
      final h2 = await h.reopen();
      expect(h2.store.planFor(today).tasks.single.targetMs, 90 * min);
      expect(h2.store.planFor(tomorrow).tasks, hasLength(1));
      expect(h2.store.selectedTask?.id, id);
    });

    test('older backups without a book still load', () {
      final json = AppData().toJson()
        ..remove('plans')
        ..remove('selectedTaskId')
        ..remove('alarm');
      final d = AppData.fromJson(json);
      expect(d.plans, isEmpty);
      expect(d.alarm, isNull);
    });

    test('empty pages are not written to storage', () {
      store.planFor(tomorrow); // just looking at a page
      expect(store.data.toJson()['plans'], isEmpty);
    });

    test('importing a backup clears a ringing alarm and a stale pick', () {
      final id = addTask(physics, 10 * min);
      store.selectTask(id);
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
