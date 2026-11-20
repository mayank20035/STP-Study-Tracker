import 'package:flutter/material.dart';

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
