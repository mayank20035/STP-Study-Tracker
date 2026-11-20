import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:stp_v2/screens/book_screen.dart';
import 'package:stp_v2/screens/home_screen.dart';
import 'package:stp_v2/state/study_store.dart';
import 'package:stp_v2/widgets/gate.dart';

import 'todo_book_test.dart' show FakeAlarms, FakeStorage;

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

Widget _wrap(StudyStore store, Widget child, {VoidCallback? openBook}) => ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        home: BookNavigator(
          openBook: openBook ?? () {},
          openToday: () {},
          openFocus: () {},
          child: child,
        ),
      ),
    );

void main() {
  final now = DateTime(2026, 3, 10, 9);

  testWidgets('the book opens on today\'s page', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final store = await _store(now);
    await tester.pumpWidget(_wrap(store, const BookScreen()));
    await tester.pump(const Duration(seconds: 2)); // cover opens
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text(DateFormat('EEEE').format(now)), findsOneWidget);
    expect(find.text('Add subject…'), findsOneWidget);
  });

  testWidgets('adding a subject from the sheet writes it on the page', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final store = await _store(now);
    store.addSubject(name: 'Physics', targetHours: 100, emoji: '🔬');
    await tester.pumpWidget(_wrap(store, const BookScreen()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.text('Add subject…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Physics'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, '2h'));
    await tester.pump();
    await tester.tap(find.text('Write it in the book'));
    await tester.pumpAndSettle();

    final tasks = store.planFor(store.todayKey).tasks;
    expect(tasks, hasLength(1));
    expect(tasks.single.targetMs, 2 * 3600000);
    expect(find.text('Physics'), findsOneWidget);

    // Tapping the line picks the task.
    await tester.tap(find.text('Physics'));
    await tester.pump();
    expect(store.selectedTask?.id, tasks.single.id);
    expect(store.canStart(store.subjects.single.id), StartGate.ok);
    await tester.pump(const Duration(seconds: 10)); // let the snackbar timer finish
  });

  testWidgets('without a picked task the Today play button is locked', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final store = await _store(now);
    store.addSubject(name: 'Maths', targetHours: 50);
    var opened = false;
    await tester.pumpWidget(_wrap(store, HomeScreen(onOpenFocus: () {}), openBook: () => opened = true));
    await tester.pump();

    expect(find.text('Plan today in your To-Do book'), findsOneWidget);
    await tester.tap(find.text('Maths'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.lock_rounded).first);
    await tester.pumpAndSettle();
    expect(store.activeTimer, isNull);
    expect(find.textContaining('Pick a task from today'), findsOneWidget);
    await tester.tap(find.text('Open book'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    await tester.pump(const Duration(seconds: 10));
  });
}
