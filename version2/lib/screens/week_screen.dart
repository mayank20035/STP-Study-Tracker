import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/day_utils.dart';
import '../models/models.dart';
import '../state/study_store.dart';
import '../widgets/common.dart';

/// Opens the week overview on the week of [dayKey]. Returns the page the
/// user tapped, if any.
Future<String?> showWeekOverview(BuildContext context, String dayKey) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => WeekScreen(initialDay: dayKey)),
  );
}

String weekRangeLabel(String weekStart) {
  final a = dateOfKey(weekStart);
  final b = dateOfKey(addDays(weekStart, 6));
  final left = a.month == b.month ? DateFormat('d').format(a) : DateFormat('d MMM').format(a);
  return '$left – ${DateFormat('d MMM yyyy').format(b)}';
}

/// The big picture: all seven pages of a week on one screen.
class WeekScreen extends StatefulWidget {
  final String initialDay;
  const WeekScreen({super.key, required this.initialDay});

  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  late String _week = weekStartOf(widget.initialDay);
  int _direction = 0;

  void _shift(int weeks) => setState(() {
        _direction = weeks;
        _week = addDays(_week, 7 * weeks);
      });

  String _relative(String todayKey) {
    final diff = dateOfKey(_week).difference(dateOfKey(weekStartOf(todayKey))).inDays ~/ 7;
    return switch (diff) {
      0 => 'This week',
      1 => 'Next week',
      -1 => 'Last week',
      > 1 => 'In $diff weeks',
      _ => '${-diff} weeks ago',
    };
  }

  Future<void> _copy() async {
    final store = context.read<StudyStore>();
    final from = _week;
    final messenger = ScaffoldMessenger.of(context);
    if (store.weekTaskCount(from) == 0) {
      await showFillFieldsDialog(context, 'This week has no tasks to copy yet.');
      return;
    }
    final target = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: const Text('Copy this week\'s tasks to…', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('From ${weekRangeLabel(from)}. Tasks already in that week are kept.'),
          ),
          for (final w in [1, 2])
            ListTile(
              leading: const Icon(Icons.content_copy_outlined),
              title: Text(w == 1 ? 'Next week' : 'In 2 weeks'),
              subtitle: Text(weekRangeLabel(addDays(from, 7 * w))),
              onTap: () => Navigator.pop(ctx, addDays(from, 7 * w)),
            ),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Choose a week…'),
            onTap: () async {
              final first = dateOfKey(addDays(from, 7));
              final d = await showDatePicker(
                context: ctx,
                initialDate: first,
                firstDate: first,
                lastDate: first.add(const Duration(days: 366)),
                helpText: 'Pick any day of the target week',
              );
              if (d != null && ctx.mounted) Navigator.pop(ctx, weekStartOf(keyOfDate(d)));
            },
          ),
        ]),
      ),
    );
    if (target == null || !mounted) return;
    final r = store.copyWeek(from, target);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(r.added == 0
            ? 'Nothing new to copy: those subjects are already planned in ${weekRangeLabel(target)}.'
            : 'Copied ${r.added} task${r.added == 1 ? '' : 's'} to ${weekRangeLabel(target)}'
                '${r.skipped > 0 ? ' (${r.skipped} already there)' : ''}.'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () {
            if (mounted) {
              setState(() {
                _direction = 1;
                _week = target;
              });
            }
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final today = store.todayKey;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Week view', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(tooltip: 'Copy this week', icon: const Icon(Icons.content_copy_outlined), onPressed: _copy),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: [
              IconButton(tooltip: 'Previous week', icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
              Expanded(
                child: Column(children: [
                  Text(weekRangeLabel(_week), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(_relative(today), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ]),
              ),
              IconButton(tooltip: 'Next week', icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
            ]),
          ),
          Expanded(
            child: GestureDetector(
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -300) _shift(1);
                if (v > 300) _shift(-1);
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, a) {
                  final incoming = child.key == ValueKey(_week);
                  final dx = (incoming ? 0.25 : -0.25) * (_direction == 0 ? 1 : _direction);
                  return FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(a),
                      child: child,
                    ),
                  );
                },
                child: _WeekGrid(
                  key: ValueKey(_week),
                  weekStart: _week,
                  currentDay: widget.initialDay,
                  onCopy: _copy,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _WeekGrid extends StatelessWidget {
  final String weekStart;
  final String currentDay;
  final VoidCallback onCopy;
  const _WeekGrid({super.key, required this.weekStart, required this.currentDay, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const pad = 12.0, gap = 10.0;
      // Two columns, four rows: all seven pages (and the copy card) fit on one screen.
      final cols = c.maxWidth > 700 ? 4 : 2;
      final rows = (8 / cols).ceil();
      final w = (c.maxWidth - pad * 2 - gap * (cols - 1)) / cols;
      final h = ((c.maxHeight - pad * 2 - gap * (rows - 1)) / rows).clamp(118.0, 400.0);
      return GridView.count(
        padding: const EdgeInsets.all(pad),
        crossAxisCount: cols,
        mainAxisSpacing: gap,
        crossAxisSpacing: gap,
        childAspectRatio: w / h,
        children: [
          for (var i = 0; i < 7; i++)
            _MiniPage(dayKey: addDays(weekStart, i), isCurrent: addDays(weekStart, i) == currentDay),
          _CopyCard(onTap: onCopy),
        ],
      );
    });
  }
}

/// A small version of one book page.
class _MiniPage extends StatelessWidget {
  final String dayKey;
  final bool isCurrent;
  const _MiniPage({required this.dayKey, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final date = dateOfKey(dayKey);
    final isToday = dayKey == store.todayKey;
    final plan = store.planFor(dayKey);
    final score = store.pageScore(dayKey);
    final status = store.pageStatus(dayKey);
    final (String? label, Color? color) = switch (status) {
      PageStatus.conquered => ('Done', Colors.green),
      PageStatus.partial => ('Partial', Colors.orange),
      PageStatus.missed => ('Missed', scheme.error),
      _ => (isToday ? 'Today' : null, isToday ? scheme.primary : null),
    };

    return Card(
      margin: EdgeInsets.zero,
      elevation: isCurrent ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isToday
            ? BorderSide(color: scheme.primary, width: 1.5)
            : isCurrent
                ? BorderSide(color: scheme.outline)
                : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pop(context, dayKey),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: LayoutBuilder(builder: (context, c) {
            // Show as many task lines as fit, then "+N more".
            final room = ((c.maxHeight - 44) / 24).floor().clamp(0, 12);
            final shown = plan.tasks.length <= room ? plan.tasks.length : (room - 1).clamp(0, 12);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(DateFormat('EEE').format(date), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(DateFormat('d MMM').format(date),
                      maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: TextStyle(fontSize: 11, color: muted)),
                ),
                if (label != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: color!.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color)),
                  ),
              ]),
              Divider(height: 10, color: scheme.outlineVariant.withValues(alpha: 0.5)),
              if (plan.tasks.isEmpty)
                Text('No tasks', style: TextStyle(fontSize: 11, color: muted))
              else ...[
                for (final t in plan.tasks.take(shown)) _MiniTask(dayKey: dayKey, task: t),
                if (shown < plan.tasks.length)
                  Text('+${plan.tasks.length - shown} more', style: TextStyle(fontSize: 10, color: muted)),
              ],
              const Spacer(),
              if (score.total > 0)
                Text('${score.done}/${score.total} done', style: TextStyle(fontSize: 10, color: muted)),
            ]);
          }),
        ),
      ),
    );
  }
}

class _MiniTask extends StatelessWidget {
  final String dayKey;
  final PlanTask task;
  const _MiniTask({required this.dayKey, required this.task});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final sub = store.subjectById(task.subjectId);
    if (sub == null) return const SizedBox.shrink();
    final progress = store.taskProgressMs(dayKey, task);
    final done = progress >= task.targetMs;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      height: 24,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(sub.emoji, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              sub.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                decoration: done ? TextDecoration.lineThrough : null,
                color: done ? muted : null,
              ),
            ),
          ),
          Text(done ? '✓' : formatDuration(task.targetMs),
              style: TextStyle(fontSize: 10, color: done ? Colors.green : muted)),
        ]),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: (progress / task.targetMs).clamp(0.0, 1.0),
            minHeight: 2.5,
            color: done ? Colors.green : sub.colorValue,
            backgroundColor: sub.colorValue.withValues(alpha: 0.12),
          ),
        ),
      ]),
    );
  }
}

class _CopyCard extends StatelessWidget {
  final VoidCallback onTap;
  const _CopyCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.content_copy_outlined, color: scheme.primary),
            const SizedBox(height: 6),
            Text('Copy this week', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary)),
            Text('to a future week', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}
