import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:stp_v2/logic/day_utils.dart';
import 'package:stp_v2/models/models.dart';
import 'package:stp_v2/screens/book_screen.dart';
import 'package:stp_v2/screens/week_screen.dart';
import 'package:stp_v2/state/study_store.dart';
import 'package:stp_v2/widgets/gate.dart';
import 'package:stp_v2/widgets/page_curl.dart';

import 'todo_book_test.dart' show FakeAlarms, FakeStorage;

const hour = 3600000;

Future<StudyStore> _store(DateTime now) async {
  final s = StudyStore(
    storage: FakeStorage(),
    alarms: FakeAlarms(),
    clock: () => now.millisecondsSinceEpoch,
    enableTicker: false,
  );
  await s.load();
  return s;
}

Widget _wrap(StudyStore store, Widget child) => ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        home: BookNavigator(openBook: () {}, openToday: () {}, openFocus: () {}, child: child),
      ),
    );

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
}

void main() {
  // ---------------------------------------------------------------- curl geometry
  group('page curl geometry', () {
    const page = Rect.fromLTWH(0, 0, 300, 500);
    const full = 300.0 * 500;

    test('flat at the start, fully turned at the end', () {
      final start = CurlGeometry.at(page, 0.0005);
      expect(CurlGeometry.area(start.front), closeTo(full, full * 0.01));
      final end = CurlGeometry.at(page, 0.9995);
      expect(CurlGeometry.area(end.front), lessThan(full * 0.01));
    });

    test('mid-turn: flat part + lifted part make the whole page', () {
      for (final t in [0.2, 0.5, 0.8]) {
        for (final top in [true, false]) {
          final g = CurlGeometry.at(page, t, fromTop: top);
          expect(CurlGeometry.area(g.front) + CurlGeometry.area(g.lifted), closeTo(full, 1e-6));
          expect(CurlGeometry.area(g.flap), lessThanOrEqualTo(CurlGeometry.area(g.lifted) + 1e-6));
          expect(CurlGeometry.area(g.flap), greaterThan(0));
        }
      }
    });

    test('more of the page is turned as progress grows', () {
      double lifted(double t) => CurlGeometry.area(CurlGeometry.at(page, t).lifted);
      expect(lifted(0.2), lessThan(lifted(0.5)));
      expect(lifted(0.5), lessThan(lifted(0.8)));
    });

    test('the flap is the mirror image of the lifted corner across the fold', () {
      final g = CurlGeometry.at(page, 0.3);
      expect(g.reflect(g.corner).dx, closeTo(g.touch.dx, 1e-6));
      expect(g.reflect(g.corner).dy, closeTo(g.touch.dy, 1e-6));
      expect(g.reflect(g.reflect(const Offset(120, 40))).dx, closeTo(120, 1e-6));
    });
  });

  // ---------------------------------------------------------------- weeks
  test('weeks start on Monday', () {
    expect(weekStartOf('2026-03-09'), '2026-03-09'); // Monday
    expect(weekStartOf('2026-03-10'), '2026-03-09'); // Tuesday
    expect(weekStartOf('2026-03-15'), '2026-03-09'); // Sunday
    expect(weekStartOf('2026-03-01'), '2026-02-23'); // across a month
    expect(weekRangeLabel('2026-03-09'), '9 – 15 Mar 2026');
    expect(weekRangeLabel('2026-03-30'), '30 Mar – 5 Apr 2026');
  });

  group('copying a week', () {
    late StudyStore store;
    late Subject physics, maths;
    const week = '2026-03-09', next = '2026-03-16';

    setUp(() async {
      store = await _store(DateTime(2026, 3, 10, 9));
      physics = store.addSubject(name: 'Physics', targetHours: 100);
      maths = store.addSubject(name: 'Maths', targetHours: 100);
    });

    test('tasks land on the same weekdays with the same study time', () {
      store.addPlanTask('2026-03-09', physics.id, 2 * hour); // Mon
      store.addPlanTask('2026-03-11', maths.id, hour); // Wed
      store.addPlanTask('2026-03-11', physics.id, hour ~/ 2);
      store.setDayNote('2026-03-11', 'notes stay behind');
      final r = store.copyWeek(week, next);
      expect(r.added, 3);
      expect(r.skipped, 0);
      expect(store.planFor('2026-03-16').tasks.single.subjectId, physics.id);
      expect(store.planFor('2026-03-16').tasks.single.targetMs, 2 * hour);
      expect(store.planFor('2026-03-18').tasks.map((t) => t.subjectId), [maths.id, physics.id]);
      expect(store.planFor('2026-03-18').note, isEmpty);
      expect(store.weekTaskCount(next), 3);
    });

    test('copies are new tasks with no progress', () {
      store.addPlanTask('2026-03-10', physics.id, hour);
      store.addSession(StudySession(
          id: 's',
          subjectId: physics.id,
          startMs: DateTime(2026, 3, 10, 6).millisecondsSinceEpoch,
          endMs: DateTime(2026, 3, 10, 7).millisecondsSinceEpoch));
      store.copyWeek(week, next);
      final src = store.planFor('2026-03-10').tasks.single;
      final copy = store.planFor('2026-03-17').tasks.single;
      expect(copy.id, isNot(src.id));
      expect(store.isTaskDone('2026-03-10', src), isTrue);
      expect(store.taskProgressMs('2026-03-17', copy), 0);
    });

    test('existing tasks are kept and duplicates skipped', () {
      store.addPlanTask('2026-03-09', physics.id, hour);
      store.addPlanTask('2026-03-09', maths.id, hour);
      store.addPlanTask('2026-03-16', physics.id, 3 * hour);
      final r = store.copyWeek(week, next);
      expect(r.added, 1);
      expect(r.skipped, 1);
      expect(store.planFor('2026-03-16').taskForSubject(physics.id)!.targetMs, 3 * hour);
      expect(store.copyWeek(week, next).added, 0, reason: 'copying twice adds nothing');
    });

    test('copying a week onto itself or an empty week does nothing', () {
      store.addPlanTask('2026-03-09', physics.id, hour);
      expect(store.copyWeek(week, week).added, 0);
      expect(store.copyWeek('2026-03-02', next).added, 0);
      expect(store.weekTaskCount(next), 0);
    });
  });

  // ---------------------------------------------------------------- widgets
  group('week view', () {
    final now = DateTime(2026, 3, 10, 9); // Tuesday

    testWidgets('shows all seven pages of the week and moves between weeks', (tester) async {
      _phone(tester);
      final store = await _store(now);
      final p = store.addSubject(name: 'Physics', targetHours: 100, emoji: '🔬');
      store.addPlanTask('2026-03-12', p.id, hour);
      await tester.pumpWidget(_wrap(store, const WeekScreen(initialDay: '2026-03-10')));
      await tester.pump();
      for (final d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
        expect(find.text(d), findsOneWidget);
      }
      expect(find.text('9 – 15 Mar 2026'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Physics'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);

      await tester.tap(find.byTooltip('Next week'));
      await tester.pumpAndSettle();
      expect(find.text('16 – 22 Mar 2026'), findsOneWidget);
      expect(find.text('Next week'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous week'));
      await tester.tap(find.byTooltip('Previous week'));
      await tester.pumpAndSettle();
      expect(find.text('Last week'), findsOneWidget);
    });

    testWidgets('copy card copies the week to next week', (tester) async {
      _phone(tester);
      final store = await _store(now);
      final p = store.addSubject(name: 'Physics', targetHours: 100);
      store.addPlanTask('2026-03-10', p.id, hour);
      await tester.pumpWidget(_wrap(store, const WeekScreen(initialDay: '2026-03-10')));
      await tester.pump();
      await tester.tap(find.text('Copy this week'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next week'));
      await tester.pumpAndSettle();
      expect(store.planFor('2026-03-17').tasks.single.subjectId, p.id);
      expect(find.textContaining('Copied 1 task'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('copying an empty week explains why nothing happens', (tester) async {
      _phone(tester);
      final store = await _store(now);
      await tester.pumpWidget(_wrap(store, const WeekScreen(initialDay: '2026-03-10')));
      await tester.pump();
      await tester.tap(find.byTooltip('Copy this week'));
      await tester.pumpAndSettle();
      expect(find.text('This week has no tasks to copy yet.'), findsOneWidget);
    });

    testWidgets('the book icon opens the week, and tapping a page opens it in the book', (tester) async {
      _phone(tester);
      final store = await _store(now);
      await tester.pumpWidget(_wrap(store, const BookScreen()));
      await tester.pump();
      expect(find.text('Tuesday'), findsOneWidget);
      await tester.tap(find.byTooltip('Week view'));
      await tester.pumpAndSettle();
      expect(find.text('Week view'), findsOneWidget);
      await tester.tap(find.text('Fri'));
      await tester.pumpAndSettle();
      expect(find.text('Week view'), findsNothing);
      expect(find.text(DateFormat('EEEE').format(DateTime(2026, 3, 13))), findsOneWidget);
      expect(store.bookPage, '2026-03-13');
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('swiping the page turns it with the curl', (tester) async {
      _phone(tester);
      final store = await _store(now);
      await tester.pumpWidget(_wrap(store, const BookScreen()));
      await tester.pump();
      final g = await tester.startGesture(tester.getCenter(find.byType(BookPage)) + const Offset(100, -200));
      await g.moveBy(const Offset(-60, 0));
      await g.moveBy(const Offset(-60, 0));
      await tester.pump();
      expect(find.byType(PageCurl), findsOneWidget);
      await g.moveBy(const Offset(-120, 0));
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('Wednesday'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
