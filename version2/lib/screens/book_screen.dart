import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/day_utils.dart';
import '../logic/stats.dart';
import '../models/models.dart';
import '../state/study_store.dart';
import '../widgets/common.dart';
import '../widgets/page_curl.dart';
import '../widgets/subject_form.dart';
import 'week_screen.dart';

// ---------------------------------------------------------------- screen

/// The To-Do book: one plain page per day. Pages turn with a paper page
/// curl: swipe left to turn to the next day, right to go back.
class BookScreen extends StatefulWidget {
  const BookScreen({super.key});

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> with SingleTickerProviderStateMixin {
  late String _key;
  String? _neighbor;
  double _progress = 0; // >0 turning to the next page, <0 back to the previous
  late final AnimationController _turn;
  double _from = 0, _to = 0;

  @override
  void initState() {
    super.initState();
    final store = context.read<StudyStore>();
    // Reopen on the page that was open last time.
    _key = store.bookPage ?? store.todayKey;
    _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..addListener(() {
        setState(() => _progress = _from + (_to - _from) * Curves.easeInOut.transform(_turn.value));
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _settle();
      });
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  void _settle() {
    setState(() {
      if (_to != 0 && _neighbor != null) _key = _neighbor!;
      _progress = 0;
      _neighbor = null;
    });
    context.read<StudyStore>().rememberBookPage(_key);
  }

  void _animateTo(double target) {
    _from = _progress;
    _to = target;
    _turn.forward(from: 0);
  }

  /// Turn to any page with the page-curl animation.
  void goTo(String key) {
    if (key == _key || _turn.isAnimating) return;
    _neighbor = key;
    _fromTop = true;
    HapticFeedback.selectionClick();
    _progress = key.compareTo(_key) > 0 ? 0.001 : -0.001;
    _animateTo(_progress.sign);
  }

  bool _dragging = false;

  /// Which corner is being turned: the top one when the swipe starts in the
  /// upper half of the page.
  bool _fromTop = true;

  void _dragStart(DragStartDetails d, double height) {
    if (_turn.isAnimating) return;
    _fromTop = d.localPosition.dy < height / 2;
  }

  void _dragBy(double delta) {
    if (_turn.isAnimating) return;
    var next = (_progress + delta).clamp(-1.0, 1.0);
    // Turning back past flat ends the turn instead of flipping the other way.
    if (_progress != 0 && next != 0 && next.sign != _progress.sign) next = 0;
    if (next == 0) {
      setState(() {
        _progress = 0;
        _neighbor = null;
      });
      return;
    }
    if (_neighbor == null || _progress == 0) _neighbor = addDays(_key, next > 0 ? 1 : -1);
    _dragging = true;
    setState(() => _progress = next);
  }

  void _release(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    if (_turn.isAnimating || _progress == 0) return;
    final v = -(d.primaryVelocity ?? 0);
    final commit = _progress.abs() > 0.3 || (v.abs() > 400 && v.sign == _progress.sign);
    if (commit) HapticFeedback.selectionClick();
    _animateTo(commit ? _progress.sign : 0);
  }

  Future<void> _openWeek() async {
    final key = await showWeekOverview(context, _key);
    if (key != null && mounted) goTo(key);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: dateOfKey(_key),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) goTo(keyOfDate(d));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final today = store.todayKey;

    Widget page(String key) => RepaintBoundary(child: BookPage(dayKey: key, onPickDate: _pickDate));

    final paper = Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surfaceContainerLow;
    Widget curl(Widget front, Widget back, double t) => PageCurl(
          front: front,
          back: back,
          t: t,
          fromTop: _fromTop,
          paper: paper,
          inset: const EdgeInsets.all(4), // the page card's margin
        );

    Widget pages;
    final n = _neighbor;
    if (_progress == 0 || n == null) {
      pages = page(_key);
    } else if (_progress > 0) {
      // Next day: this page curls away from its right corner.
      pages = curl(page(_key), page(n), _progress);
    } else {
      // Previous day: that page uncurls back over this one.
      pages = curl(page(n), page(_key), 1 + _progress);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('To-Do Book', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Week view',
            icon: const Icon(Icons.auto_stories_outlined),
            onPressed: _openWeek,
          ),
          IconButton(
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => goTo(addDays(_key, -1)),
          ),
          IconButton(
            tooltip: 'Pick a date',
            icon: const Icon(Icons.calendar_today_outlined, size: 20),
            onPressed: _pickDate,
          ),
          IconButton(
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => goTo(addDays(_key, 1)),
          ),
        ],
      ),
      floatingActionButton: _key == today
          ? null
          : FloatingActionButton.small(
              heroTag: 'book_today',
              tooltip: 'Back to today',
              onPressed: () => goTo(today),
              child: const Icon(Icons.today),
            ),
      body: LayoutBuilder(
        builder: (context, c) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: GestureDetector(
            onHorizontalDragStart: (d) => _dragStart(d, c.maxHeight),
            onHorizontalDragUpdate: (d) => _dragBy(-d.delta.dx / c.maxWidth * 1.1),
            onHorizontalDragEnd: _release,
            child: pages,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- page

/// One day: date, the planned subjects, a note, and the daily quote at the bottom.
class BookPage extends StatelessWidget {
  final String dayKey;
  final VoidCallback onPickDate;
  const BookPage({super.key, required this.dayKey, required this.onPickDate});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final isToday = dayKey == store.todayKey;
    final date = dateOfKey(dayKey);
    final plan = store.planFor(dayKey);
    final score = store.pageScore(dayKey);
    final status = store.pageStatus(dayKey);
    final quote = motivationalQuotes[dayKey.hashCode.abs() % motivationalQuotes.length];

    return Card(
      elevation: 1.5,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            children: [
              InkWell(
                onTap: onPickDate,
                borderRadius: BorderRadius.circular(8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(DateFormat('EEEE').format(date),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      Text(DateFormat('d MMM yyyy').format(date), style: TextStyle(fontSize: 12, color: muted)),
                    ]),
                  ),
                  if (isToday) _Pill('Today', scheme.primary),
                  if (status == PageStatus.conquered) _Pill('Done', Colors.green),
                  if (status == PageStatus.partial) _Pill('Partial', Colors.orange),
                  if (status == PageStatus.missed) _Pill('Missed', scheme.error),
                ]),
              ),
              if (score.total > 0) ...[
                const SizedBox(height: 4),
                Text('${score.done}/${score.total} done', style: TextStyle(fontSize: 12, color: muted)),
              ],
              const SizedBox(height: 10),
              Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 6),
              if (plan.tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('No tasks', style: TextStyle(fontSize: 13, color: muted)),
                )
              else
                for (final t in plan.tasks) _TaskLine(dayKey: dayKey, task: t),
              _AddLine(dayKey: dayKey),
              const SizedBox(height: 12),
              _NoteRow(dayKey: dayKey),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Text('“$quote”',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: muted.withValues(alpha: 0.8))),
        ),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ---------------------------------------------------------------- task line

class _TaskLine extends StatelessWidget {
  final String dayKey;
  final PlanTask task;
  const _TaskLine({required this.dayKey, required this.task});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final sub = store.subjectById(task.subjectId);
    if (sub == null) return const SizedBox.shrink();
    final progress = store.taskProgressMs(dayKey, task);
    final done = progress >= task.targetMs;
    final selected = store.isSelected(dayKey, task);
    final running = store.activeTimer?.taskId == task.id;

    Future<void> onTap() async {
      // Any unfinished task can be picked: a missed day, today or ahead.
      if (!selected && !done) {
        store.selectTask(dayKey, task.id);
        return;
      }
      await _taskActions(context, dayKey, task);
    }

    final String status;
    if (done) {
      status = '${formatDuration(progress)} · done';
    } else if (running) {
      status = '${formatClock(store.taskRemainingMs(dayKey, task))} left';
    } else {
      status = '${formatDuration(progress)} / ${formatDuration(task.targetMs)}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? sub.colorValue.withValues(alpha: 0.08) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: selected ? BorderSide(color: sub.colorValue.withValues(alpha: 0.6)) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onLongPress: () => _taskActions(context, dayKey, task),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(done ? Icons.check_circle : Icons.circle_outlined,
                    size: 18, color: done ? Colors.green : muted),
                const SizedBox(width: 8),
                Text(sub.emoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    sub.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done ? muted : null,
                    ),
                  ),
                ),
                Text(formatDuration(task.targetMs), style: TextStyle(fontSize: 13, color: muted)),
              ]),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (progress / task.targetMs).clamp(0.0, 1.0),
                          minHeight: 4,
                          color: done ? Colors.green : sub.colorValue,
                          backgroundColor: sub.colorValue.withValues(alpha: 0.12),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(status, style: TextStyle(fontSize: 11, color: muted)),
                    ]),
                  ),
                  if (selected && !done) ...[
                    const SizedBox(width: 10),
                    _MiniButton(
                      icon: running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: running ? scheme.error : sub.colorValue,
                      onTap: () => store.toggleTimer(sub.id),
                    ),
                  ],
                  if (done)
                    TextButton(
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12)),
                      onPressed: () => store.extendTask(dayKey, task.id, 15),
                      child: const Text('+15m'),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _MiniButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(5), child: Icon(icon, color: Colors.white, size: 18)),
      ),
    );
  }
}

Future<void> _taskActions(BuildContext context, String dayKey, PlanTask task) async {
  final store = context.read<StudyStore>();
  final sub = store.subjectById(task.subjectId);
  if (sub == null) return;
  final selected = store.isSelected(dayKey, task);
  final done = store.isTaskDone(dayKey, task);
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: SubjectAvatar(sub, size: 40),
          title: Text(sub.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('Target ${formatDuration(task.targetMs)} · studied '
              '${formatDuration(store.taskProgressMs(dayKey, task))}'),
        ),
        if (!selected && !done)
          ListTile(
            leading: const Icon(Icons.push_pin_outlined),
            title: const Text('Pick this task'),
            onTap: () => Navigator.pop(ctx, 'select'),
          ),
        if (selected)
          ListTile(
            leading: const Icon(Icons.push_pin),
            title: const Text('Unpick'),
            onTap: () => Navigator.pop(ctx, 'unselect'),
          ),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Change study time'),
          onTap: () => Navigator.pop(ctx, 'edit'),
        ),
        ListTile(
          leading: const Icon(Icons.more_time),
          title: const Text('+15 minutes'),
          onTap: () => Navigator.pop(ctx, 'extend'),
        ),
        ListTile(
          leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
          title: const Text('Remove from this page'),
          onTap: () => Navigator.pop(ctx, 'remove'),
        ),
      ]),
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'select':
      store.selectTask(dayKey, task.id);
    case 'unselect':
      store.clearSelection();
    case 'extend':
      store.extendTask(dayKey, task.id, 15);
    case 'edit':
      final ms = await showDurationPicker(context, initialMs: task.targetMs, title: 'Study time for ${sub.name}');
      if (ms != null) store.updatePlanTaskTarget(dayKey, task.id, ms);
    case 'remove':
      if (await confirmDialog(context,
          title: 'Remove ${sub.name}?',
          message: 'It disappears from this page. Time you already studied is kept.',
          confirm: 'Remove')) {
        store.removePlanTask(dayKey, task.id);
      }
  }
}

Future<void> showAddTaskSheet(BuildContext context, String dayKey) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AddTaskSheet(dayKey: dayKey),
  );
}

class _AddTaskSheet extends StatefulWidget {
  final String dayKey;
  const _AddTaskSheet({required this.dayKey});

  @override
  State<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<_AddTaskSheet> {
  String? _subjectId;
  int _minutes = 60;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final plan = store.planFor(widget.dayKey);
    final available = store.subjects.where((s) => plan.taskForSubject(s.id) == null).toList();
    final scheme = Theme.of(context).colorScheme;

    if (store.subjects.isEmpty) {
      return SafeArea(
        child: EmptyState(
          emoji: '📚',
          title: 'No subjects yet',
          body: 'The book only lists subjects you created. Make one first!',
          action: FilledButton.icon(
            onPressed: () => showSubjectForm(context),
            icon: const Icon(Icons.add),
            label: const Text('Create a subject'),
          ),
        ),
      );
    }
    if (available.isEmpty) {
      return const SafeArea(
        child: EmptyState(
          emoji: '✅',
          title: 'Every subject is on this page',
          body: 'Change a task\'s time by long-pressing it on the page.',
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add to ${prettyDayKey(widget.dayKey, store.todayKey)}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Subject', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in available)
              ChoiceChip(
                avatar: Text(s.emoji),
                label: Text(s.name),
                selected: _subjectId == s.id,
                selectedColor: s.colorValue.withValues(alpha: 0.25),
                onSelected: (_) => setState(() => _subjectId = s.id),
              ),
          ]),
          const SizedBox(height: 18),
          Text('Time', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          DurationStepper(minutes: _minutes, onChanged: (m) => setState(() => _minutes = m)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
              onPressed: () {
                if (_subjectId == null) {
                  showFillFieldsDialog(context, 'Please pick a subject.');
                  return;
                }
                final r = store.addPlanTask(widget.dayKey, _subjectId!, _minutes * 60000);
                if (r == PlanResult.ok) {
                  Navigator.pop(context);
                } else {
                  showFillFieldsDialog(context, switch (r) {
                    PlanResult.duplicateSubject => 'That subject is already on this page.',
                    PlanResult.invalidTarget => 'Pick a time between 1 minute and 24 hours.',
                    _ => 'Could not add that subject.',
                  });
                }
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// Hours + minutes stepper with quick presets.
class DurationStepper extends StatelessWidget {
  final int minutes;
  final ValueChanged<int> onChanged;
  const DurationStepper({super.key, required this.minutes, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    void set(int v) => onChanged(v.clamp(5, 24 * 60));
    Widget stepper(String label, String value, VoidCallback minus, VoidCallback plus) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(onPressed: minus, icon: const Icon(Icons.remove_circle_outline)),
                  Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  IconButton(onPressed: plus, icon: const Icon(Icons.add_circle_outline)),
                ]),
              ]),
            ),
          ),
        );
    return Column(children: [
      Row(children: [
        stepper('HOURS', '$h', () => set(minutes - 60), () => set(minutes + 60)),
        const SizedBox(width: 10),
        stepper('MINUTES', m.toString().padLeft(2, '0'), () => set(minutes - 5), () => set(minutes + 5)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final v in [30, 45, 60, 90, 120, 180, 240])
          ChoiceChip(
            label: Text(formatDuration(v * 60000)),
            selected: minutes == v,
            onSelected: (_) => set(v),
          ),
      ]),
    ]);
  }
}

Future<int?> showDurationPicker(BuildContext context, {required int initialMs, required String title}) {
  var minutes = (initialMs / 60000).round().clamp(5, 24 * 60);
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: DurationStepper(minutes: minutes, onChanged: (v) => setState(() => minutes = v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, minutes * 60000), child: const Text('Save')),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------- add line

class _AddLine extends StatelessWidget {
  final String dayKey;
  const _AddLine({required this.dayKey});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        onPressed: () => showAddTaskSheet(context, dayKey),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add subject'),
      ),
    );
  }
}

// ---------------------------------------------------------------- note

class _NoteRow extends StatelessWidget {
  final String dayKey;
  const _NoteRow({required this.dayKey});

  static const moods = ['😫', '😕', '😐', '🙂', '🤩'];

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final plan = store.planFor(dayKey);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Note', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: muted)),
        const Spacer(),
        for (var i = 0; i < moods.length; i++)
          GestureDetector(
            onTap: () => store.setDayMood(dayKey, plan.mood == i ? null : i),
            child: Opacity(
              opacity: plan.mood == null || plan.mood == i ? 1 : 0.3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Text(moods[i], style: const TextStyle(fontSize: 15)),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 4),
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final t = await promptText(context, title: 'Note', initial: plan.note, required: false);
          if (t != null) store.setDayNote(dayKey, t);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              plan.note.isEmpty ? 'Add a note' : plan.note,
              style: TextStyle(fontSize: 13, color: plan.note.isEmpty ? muted.withValues(alpha: 0.7) : null),
            ),
          ),
        ),
      ),
    ]);
  }
}
