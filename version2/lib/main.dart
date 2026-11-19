import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'logic/achievements.dart';
import 'screens/analytics_screen.dart';
import 'screens/focus_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/rankings_screen.dart';
import 'state/study_store.dart';
import 'theme.dart';

final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = StudyStore();
  await store.load();
  runApp(ChangeNotifierProvider.value(value: store, child: const StpApp()));
}

class StpApp extends StatelessWidget {
  const StpApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.select<StudyStore, (ThemeMode, int)>(
        (s) => (s.settings.themeMode, s.settings.accentIndex));
    return MaterialApp(
      title: 'STP v2',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      themeMode: settings.$1,
      theme: buildTheme(Brightness.light, settings.$2),
      darkTheme: buildTheme(Brightness.dark, settings.$2),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  int _index = 0;
  late final StudyStore _store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store = context.read<StudyStore>();
    _store.pomodoroEvents.addListener(_onPomodoroEvent);
    _store.newAchievements.addListener(_onAchievements);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.pomodoroEvents.removeListener(_onPomodoroEvent);
    _store.newAchievements.removeListener(_onAchievements);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _store.flush();
    }
  }

  void _onPomodoroEvent() {
    final e = _store.pomodoroEvents.value;
    if (e == null) return;
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(e.message)));
  }

  void _onAchievements() {
    final list = _store.newAchievements.value;
    if (list.isEmpty || !mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AchievementUnlockedDialog(achievements: list),
    );
  }

  @override
  Widget build(BuildContext context) {
    final running = context.select<StudyStore, bool>((s) => s.activeTimer != null || s.pomodoro != null);
    final pages = [
      HomeScreen(onOpenFocus: () => setState(() => _index = 1)),
      const FocusScreen(),
      const AnalyticsScreen(),
      const RankingsScreen(),
      const ProfileScreen(),
    ];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            const NavigationDestination(
                icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Today'),
            NavigationDestination(
              icon: Badge(isLabelVisible: running, smallSize: 8, child: const Icon(Icons.timer_outlined)),
              selectedIcon: const Icon(Icons.timer_rounded),
              label: 'Focus',
            ),
            const NavigationDestination(
                icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Insights'),
            const NavigationDestination(
                icon: Icon(Icons.emoji_events_outlined),
                selectedIcon: Icon(Icons.emoji_events),
                label: 'Ranks'),
            const NavigationDestination(
                icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

class AchievementUnlockedDialog extends StatelessWidget {
  final List<Achievement> achievements;
  const AchievementUnlockedDialog({super.key, required this.achievements});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Achievement unlocked!', textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in achievements)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.3, end: 1),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.elasticOut,
                  builder: (_, v, child) => Transform.scale(scale: v, child: child),
                  child: Text(a.emoji, style: const TextStyle(fontSize: 56)),
                ),
                Text(a.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(a.description, textAlign: TextAlign.center),
              ]),
            ),
        ],
      ),
      actions: [
        Center(child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Awesome!'))),
      ],
    );
  }
}
