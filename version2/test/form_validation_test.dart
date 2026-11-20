import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stp_v2/screens/book_screen.dart';
import 'package:stp_v2/state/study_store.dart';
import 'package:stp_v2/widgets/common.dart';
import 'package:stp_v2/widgets/subject_form.dart';

import 'todo_book_test.dart' show FakeAlarms, FakeStorage;

Future<StudyStore> _store() async {
  final now = DateTime(2026, 3, 10, 9);
  final s = StudyStore(
    storage: FakeStorage(),
    alarms: FakeAlarms(),
    clock: () => now.millisecondsSinceEpoch,
    enableTicker: false,
  );
  await s.load();
  return s;
}

/// A screen with one button that runs [onTap] with a context under the store.
Widget _host(StudyStore store, void Function(BuildContext) onTap) => ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(onPressed: () => onTap(context), child: const Text('open')),
            ),
          ),
        ),
      ),
    );

const _popupTitle = 'Fill in the details';

void _bigScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
}

void main() {
  test('missingFieldsMessage joins field names', () {
    expect(missingFieldsMessage(['Subject name']), 'Please fill in Subject name.');
    expect(missingFieldsMessage(['A', 'B']), 'Please fill in A and B.');
    expect(missingFieldsMessage(['A', 'B', 'C']), 'Please fill in A, B and C.');
  });

  group('subject form', () {
    testWidgets('empty form: popup names both fields, nothing is saved', (tester) async {
      _bigScreen(tester);
      final store = await _store();
      await tester.pumpWidget(_host(store, (c) => showSubjectForm(c)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create subject'));
      await tester.pumpAndSettle();
      expect(find.text(_popupTitle), findsOneWidget);
      expect(find.text('Please fill in Subject name and Target hours.'), findsOneWidget);
      expect(store.subjects, isEmpty);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text(_popupTitle), findsNothing);
      expect(find.text('New subject'), findsOneWidget, reason: 'the form stays open');
    });

    testWidgets('only the missing field is named', (tester) async {
      _bigScreen(tester);
      final store = await _store();
      await tester.pumpWidget(_host(store, (c) => showSubjectForm(c)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Subject name'), 'Physics');
      await tester.tap(find.text('Create subject'));
      await tester.pumpAndSettle();
      expect(find.text('Please fill in Target hours.'), findsOneWidget);
      expect(store.subjects, isEmpty);
    });

    testWidgets('whitespace-only name counts as empty', (tester) async {
      _bigScreen(tester);
      final store = await _store();
      await tester.pumpWidget(_host(store, (c) => showSubjectForm(c)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Subject name'), '   ');
      await tester.enterText(find.widgetWithText(TextField, 'Target hours'), '10');
      await tester.tap(find.text('Create subject'));
      await tester.pumpAndSettle();
      expect(find.text('Please fill in Subject name.'), findsOneWidget);
      expect(store.subjects, isEmpty);
    });

    testWidgets('invalid target shows its own popup', (tester) async {
      _bigScreen(tester);
      final store = await _store();
      await tester.pumpWidget(_host(store, (c) => showSubjectForm(c)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Subject name'), 'Physics');
      await tester.enterText(find.widgetWithText(TextField, 'Target hours'), '0');
      await tester.tap(find.text('Create subject'));
      await tester.pumpAndSettle();
      expect(find.text('Target hours must be a number above 0.'), findsOneWidget);
      expect(store.subjects, isEmpty);
    });

    testWidgets('filled form saves without a popup', (tester) async {
      _bigScreen(tester);
      final store = await _store();
      await tester.pumpWidget(_host(store, (c) => showSubjectForm(c)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Subject name'), 'Physics');
      await tester.enterText(find.widgetWithText(TextField, 'Target hours'), '100');
      await tester.tap(find.text('Create subject'));
      await tester.pumpAndSettle();
      expect(find.text(_popupTitle), findsNothing);
      expect(store.subjects.single.name, 'Physics');
      expect(find.text('New subject'), findsNothing);
    });
  });

  testWidgets('book: Add without picking a subject shows the popup', (tester) async {
    _bigScreen(tester);
    final store = await _store();
    store.addSubject(name: 'Maths', targetHours: 50);
    await tester.pumpWidget(_host(store, (c) => showAddTaskSheet(c, store.todayKey)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Please pick a subject.'), findsOneWidget);
    expect(store.planFor(store.todayKey).tasks, isEmpty);
  });

  group('text prompt', () {
    testWidgets('required prompt stays open and shows the popup when empty', (tester) async {
      final store = await _store();
      String? result = 'unset';
      await tester.pumpWidget(_host(store, (c) async => result = await promptText(c, title: 'New category')));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Please fill in New category.'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget, reason: 'prompt is still open');
      expect(result, 'unset');

      await tester.enterText(find.byType(TextField), 'Exam prep');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result, 'Exam prep');
    });

    testWidgets('optional prompt (day note) can be saved empty', (tester) async {
      final store = await _store();
      String? result;
      await tester.pumpWidget(_host(
          store, (c) async => result = await promptText(c, title: 'Note', initial: 'x', required: false)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text(_popupTitle), findsNothing);
      expect(result, '');
    });

    testWidgets('number prompt rejects non-numbers', (tester) async {
      final store = await _store();
      String? result;
      await tester.pumpWidget(_host(
          store,
          (c) async => result = await promptText(c,
              title: 'Daily goal (minutes)', keyboard: TextInputType.number, validate: positiveWholeNumber)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter a whole number above 0.'), findsOneWidget);
      expect(result, isNull);
    });
  });
}
