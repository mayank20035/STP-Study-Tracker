import 'package:flutter/material.dart';

import '../state/study_store.dart';

/// Lets any screen jump to the To-Do book tab.
class BookNavigator extends InheritedWidget {
  final VoidCallback openBook;
  final VoidCallback openToday;
  final VoidCallback openFocus;
  const BookNavigator({
    super.key,
    required this.openBook,
    required this.openToday,
    required this.openFocus,
    required super.child,
  });

  static BookNavigator? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BookNavigator>();

  @override
  bool updateShouldNotify(BookNavigator oldWidget) => false;
}

String gateMessage(StartGate gate, {String? taskSubject}) => switch (gate) {
      StartGate.ok => '',
      StartGate.noTaskSelected => '📖 Pick a task from today\'s page in your To-Do book first.',
      StartGate.wrongSubject => '🔒 Today\'s picked task is ${taskSubject ?? 'another subject'}. '
          'Pick this subject in your book to time it.',
      StartGate.targetReached => '🎯 Target already reached! Add more time in your book to continue.',
    };

/// Shows why a timer could not start, with a shortcut to the book.
void showGateSnack(BuildContext context, StudyStore store, StartGate gate) {
  if (gate == StartGate.ok) return;
  final sel = store.selectedTask;
  final name = sel == null ? null : store.subjectById(sel.subjectId)?.name;
  final nav = BookNavigator.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(gateMessage(gate, taskSubject: name)),
      action: nav == null ? null : SnackBarAction(label: 'Open book', onPressed: nav.openBook),
    ));
}
