import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/day_utils.dart';
import '../logic/stats.dart';
import '../models/models.dart';
import '../state/study_store.dart';
import '../widgets/common.dart';
import '../widgets/gate.dart';

/// Distraction-free focus timer: stopwatch or Pomodoro.
class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  String? _subjectId;
  String? _chapterId;
  bool _pomodoroMode = true;
  final int _quote = math.Random().nextInt(motivationalQuotes.length);

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final scheme = Theme.of(context).colorScheme;
    final p = store.pomodoro;
    final t = store.activeTimer;
    final runningSubject = store.subjectById(p?.subjectId ?? t?.subjectId);
    final picked = store.subjectById(store.selectedTask?.subjectId);
    final Subject? sub = runningSubject ?? picked;
    if (_subjectId != picked?.id) {
      _subjectId = picked?.id;
      _chapterId = null;
    }
    final color = sub?.colorValue ?? scheme.primary;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.22), Theme.of(context).scaffoldBackgroundColor],
          ),
        ),
        child: SafeArea(
          child: sub == null
              ? Center(
                  child: EmptyState(
                    emoji: '📖',
                    title: 'Pick a task first',
                    body: "Focus sessions unlock for the subject you pick on today's page of your To-Do book.",
                    action: FilledButton.icon(
                      onPressed: BookNavigator.of(context)?.openBook,
                      icon: const Icon(Icons.menu_book),
                      label: const Text('Open my To-Do book'),
                    ),
                  ),
                )
              : runningSubject != null
                  ? _RunningView(subject: runningSubject, color: color)
                  : _SetupView(
                      subject: sub,
                      chapterId: _chapterId,
                      pomodoroMode: _pomodoroMode,
                      quote: motivationalQuotes[_quote],
                      onSubject: (id) => setState(() {
                        _subjectId = id;
                        _chapterId = null;
                      }),
                      onChapter: (id) => setState(() => _chapterId = id),
                      onMode: (v) => setState(() => _pomodoroMode = v),
                    ),
        ),
      ),
    );
  }
}

class _SetupView extends StatelessWidget {
  final Subject subject;
  final String? chapterId;
  final bool pomodoroMode;
  final String quote;
  final ValueChanged<String> onSubject;
  final ValueChanged<String?> onChapter;
  final ValueChanged<bool> onMode;

  const _SetupView({
    required this.subject,
    required this.chapterId,
    required this.pomodoroMode,
    required this.quote,
    required this.onSubject,
    required this.onChapter,
    required this.onMode,
  });

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final st = store.settings;
    final scheme = Theme.of(context).colorScheme;
    final chapters = subject.chapters.where((c) => !c.completed).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const Text('Focus', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        Text('“$quote”', style: TextStyle(fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 24),
        Center(
          child: ProgressRing(
            progress: pomodoroMode ? 1 : 0,
            size: 230,
            stroke: 14,
            color: subject.colorValue,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(subject.emoji, style: const TextStyle(fontSize: 40)),
              Text(pomodoroMode ? '${st.pomodoroWorkMin}:00' : '00:00:00',
                  style: const TextStyle(
                      fontSize: 40, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
              Text(pomodoroMode ? 'Pomodoro' : 'Stopwatch', style: TextStyle(color: scheme.onSurfaceVariant)),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, icon: Text('🍅'), label: Text('Pomodoro')),
              ButtonSegment(value: false, icon: Icon(Icons.timer_outlined), label: Text('Stopwatch')),
            ],
            selected: {pomodoroMode},
            onSelectionChanged: (s) => onMode(s.first),
          ),
        ),
        if (pomodoroMode)
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.tune, size: 18),
              label: Text('${st.pomodoroWorkMin}m focus · ${st.pomodoroShortBreakMin}m break · '
                  '${st.pomodoroLongBreakMin}m long break'),
              onPressed: () => showPomodoroSettings(context),
            ),
          ),
        const SectionTitle("Today's pick"),
        Card(
          child: ListTile(
            leading: SubjectAvatar(subject, size: 40),
            title: Text(subject.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Builder(builder: (_) {
              final task = store.selectedTask!;
              return Text('${formatDuration(store.taskRemainingMs(store.todayKey, task))} left of '
                  '${formatDuration(task.targetMs)} today');
            }),
            trailing: TextButton(
              onPressed: BookNavigator.of(context)?.openBook,
              child: const Text('Change'),
            ),
          ),
        ),
        if (chapters.isNotEmpty) ...[
          const SectionTitle('Chapter'),
          Wrap(spacing: 8, runSpacing: 4, children: [
            ChoiceChip(label: const Text('General'), selected: chapterId == null, onSelected: (_) => onChapter(null)),
            for (final c in chapters)
              ChoiceChip(label: Text(c.name), selected: chapterId == c.id, onSelected: (_) => onChapter(c.id)),
          ]),
        ],
        const SizedBox(height: 28),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: subject.colorValue,
            padding: const EdgeInsets.symmetric(vertical: 18),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          icon: const Icon(Icons.play_arrow_rounded, size: 28),
          label: Text(pomodoroMode ? 'Start Pomodoro' : 'Start focus'),
          onPressed: () => showGateSnack(
            context,
            store,
            pomodoroMode ? store.startPomodoro(subject.id, chapterId) : store.startTimer(subject.id, chapterId),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text('Today: ${formatDuration(store.todayMs)} · ${store.pomodorosCompleted} 🍅 all-time',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

class _RunningView extends StatelessWidget {
  final Subject subject;
  final Color color;
  const _RunningView({required this.subject, required this.color});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final scheme = Theme.of(context).colorScheme;
    final p = store.pomodoro;
    final chapter = subject.chapterById(p?.chapterId ?? store.activeTimer?.chapterId);

    final double progress;
    final String clock;
    final String phaseLabel;
    Color ringColor = color;
    if (p != null) {
      final len = store.phaseLengthMs(p.phase);
      final remaining = store.pomodoroRemainingMs;
      progress = len == 0 ? 0 : 1 - remaining / len;
      clock = formatShortClock(remaining);
      phaseLabel = switch (p.phase) {
        PomodoroPhase.work => p.isPaused ? 'Paused' : 'Focus',
        PomodoroPhase.shortBreak => 'Short break',
        PomodoroPhase.longBreak => 'Long break',
      };
      if (p.isBreak) ringColor = Colors.teal;
    } else {
      final live = store.liveMs;
      final task = store.selectedTask;
      progress = task != null && task.subjectId == subject.id
          ? store.taskProgressMs(store.todayKey, task) / task.targetMs
          : (live % 3600000) / 3600000;
      clock = formatClock(live);
      phaseLabel = 'Focusing';
    }
    final left = store.timerRemainingMs;

    final cycles = store.settings.pomodoroCyclesBeforeLong;
    final doneInCycle = p == null ? 0 : p.completedWork % cycles;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Row(children: [
          SubjectAvatar(subject),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(subject.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(chapter?.name ?? 'General study', style: TextStyle(color: scheme.onSurfaceVariant)),
            ]),
          ),
        ]),
        const Spacer(),
        ProgressRing(
          progress: progress,
          size: 280,
          stroke: 16,
          color: ringColor,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(phaseLabel.toUpperCase(),
                style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w800, color: ringColor)),
            const SizedBox(height: 4),
            Text(clock,
                style: const TextStyle(
                    fontSize: 52, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
            if (p != null) ...[
              const SizedBox(height: 8),
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < cycles; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Text(i < doneInCycle ? '🍅' : '⚪', style: const TextStyle(fontSize: 14)),
                  ),
              ]),
            ],
          ]),
        ),
        const SizedBox(height: 16),
        Text(
          left != null
              ? '⏰ Alarm in ${formatClock(left)} — target ${formatDuration(store.selectedTask?.targetMs ?? 0)}'
              : 'Today ${formatDuration(store.todayMs)}',
          style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (p != null) ...[
            _RoundButton(
              icon: Icons.skip_next_rounded,
              label: 'Skip',
              onTap: store.skipPomodoroPhase,
            ),
            const SizedBox(width: 20),
            _RoundButton(
              icon: p.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              label: p.isPaused ? 'Resume' : 'Pause',
              big: true,
              color: color,
              onTap: p.isPaused ? store.resumePomodoro : store.pausePomodoro,
            ),
            const SizedBox(width: 20),
          ],
          _RoundButton(
            icon: Icons.stop_rounded,
            label: p == null ? 'Stop & save' : 'Stop',
            big: p == null,
            color: scheme.error,
            onTap: store.stopTimer,
          ),
        ]),
        const SizedBox(height: 12),
      ]),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool big;
  final Color? color;
  const _RoundButton({required this.icon, required this.label, required this.onTap, this.big = false, this.color});

  @override
  Widget build(BuildContext context) {
    final size = big ? 80.0 : 60.0;
    final bg = color ?? Theme.of(context).colorScheme.surfaceContainerHighest;
    final fg = color == null ? Theme.of(context).colorScheme.onSurface : Colors.white;
    return Column(children: [
      Material(
        color: bg,
        shape: const CircleBorder(),
        elevation: big ? 6 : 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: size, height: size, child: Icon(icon, color: fg, size: size * 0.5)),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    ]);
  }
}

void showPomodoroSettings(BuildContext context) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) => Consumer<StudyStore>(builder: (ctx, store, _) {
      final st = store.settings;
      Widget row(String label, int value, int min, int max, void Function(int) set) => ListTile(
            title: Text(label),
            subtitle: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              label: '$value',
              onChanged: (v) => store.updateSettings((s) => set(v.round())),
            ),
            trailing: Text('$value', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          );
      return SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 16), children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Pomodoro settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          row('Focus (min)', st.pomodoroWorkMin, 5, 90, (v) => st.pomodoroWorkMin = v),
          row('Short break (min)', st.pomodoroShortBreakMin, 1, 30, (v) => st.pomodoroShortBreakMin = v),
          row('Long break (min)', st.pomodoroLongBreakMin, 5, 60, (v) => st.pomodoroLongBreakMin = v),
          row('Pomodoros before long break', st.pomodoroCyclesBeforeLong, 2, 8,
              (v) => st.pomodoroCyclesBeforeLong = v),
          SwitchListTile(
            title: const Text('Auto-start next focus block'),
            value: st.pomodoroAutoStart,
            onChanged: (v) => store.updateSettings((s) => s.pomodoroAutoStart = v),
          ),
        ]),
      );
    }),
  );
}
