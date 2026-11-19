import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/day_utils.dart';
import '../models/models.dart';
import '../state/study_store.dart';
import '../widgets/common.dart';
import '../widgets/subject_form.dart';
import 'session_log_screen.dart';
import 'subject_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onOpenFocus;
  const HomeScreen({super.key, required this.onOpenFocus});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Burning the midnight oil';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final streak = store.streak;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showSubjectForm(context),
        icon: const Icon(Icons.add),
        label: const Text('Subject'),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_greeting()}, ${store.profile.name.split(' ').first} ${store.profile.avatar}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      Text(DateFormat('EEEE, d MMMM').format(DateTime.now()),
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ]),
                  ),
                  _StreakChip(current: streak.current, todayDone: streak.todayDone),
                  _HomeMenu(),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(child: _HeroCard()),
            ),
            // Always present so the slivers below keep their state.
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, store.activeTimer != null || store.pomodoro != null ? 12 : 0, 16, 0),
              sliver: SliverToBoxAdapter(
                child: store.activeTimer != null || store.pomodoro != null
                    ? _ActiveTimerBanner(onOpenFocus: onOpenFocus)
                    : const SizedBox.shrink(),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: SectionTitle('Subjects',
                    trailing: Text('${store.subjects.length}',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
              ),
            ),
            if (store.subjects.isEmpty)
              SliverToBoxAdapter(
                child: EmptyState(
                  emoji: '📚',
                  title: 'Add your first subject',
                  body: 'Create subjects, split them into chapters and start tracking your study time.',
                  action: FilledButton.icon(
                    onPressed: () => showSubjectForm(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add subject'),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList.separated(
                  itemCount: store.subjects.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => SubjectCard(key: ValueKey(store.subjects[i].id), subject: store.subjects[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StreakChip extends StatelessWidget {
  final int current;
  final bool todayDone;
  const _StreakChip({required this.current, required this.todayDone});

  @override
  Widget build(BuildContext context) {
    final active = current > 0;
    return Tooltip(
      message: todayDone ? 'Streak secured for today!' : 'Study today to keep your streak',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.orange.withValues(alpha: 0.15) : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(active ? '🔥' : '🧊', style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 4),
          Text('$current',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: active ? Colors.orange.shade700 : null, fontSize: 16)),
        ]),
      ),
    );
  }
}

class _HomeMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (v) {
        switch (v) {
          case 'levels':
            showLevelsSheet(context);
          case 'filter':
            showFilterSheet(context);
          case 'reorder':
            showReorderSheet(context);
          case 'log':
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SessionLogScreen()));
          case 'manual':
            if (context.read<StudyStore>().subjects.isEmpty) {
              showSnack(context, 'Add a subject first');
            } else {
              showSessionEditor(context);
            }
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'manual', child: ListTile(leading: Icon(Icons.more_time), title: Text('Add session manually'))),
        PopupMenuItem(value: 'log', child: ListTile(leading: Icon(Icons.history), title: Text('Session log'))),
        PopupMenuItem(value: 'levels', child: ListTile(leading: Icon(Icons.flag_outlined), title: Text('Levels & goals'))),
        PopupMenuItem(value: 'filter', child: ListTile(leading: Icon(Icons.filter_list), title: Text('Count filter'))),
        PopupMenuItem(value: 'reorder', child: ListTile(leading: Icon(Icons.swap_vert), title: Text('Reorder subjects'))),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final scheme = Theme.of(context).colorScheme;
    final today = store.todayMs;
    final goalMs = store.settings.dailyGoalMinutes * 60000;
    final dayProgress = goalMs == 0 ? 0.0 : today / goalMs;
    final level = store.activeGoal;
    final filtered = store.filteredTotalMs;
    final levelPct = level.hours == 0 ? 0.0 : filtered / 3600000 / level.hours;
    final filterOn = store.settings.homeFilterIds != null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.6)!],
        ),
        boxShadow: [
          BoxShadow(color: scheme.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('TODAY',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 12)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(formatClock(today),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    )),
              ),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: () => _editDailyGoal(context),
                child: Row(children: [
                  Text('Daily goal ${formatDuration(goalMs)}',
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit, size: 14, color: Colors.white70),
                ]),
              ),
            ]),
          ),
          ProgressRing(
            progress: dayProgress,
            size: 92,
            stroke: 10,
            color: Colors.white,
            trackColor: Colors.white24,
            child: Text(dayProgress >= 1 ? '✅' : '${(dayProgress * 100).clamp(0, 999).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          ),
        ]),
        const SizedBox(height: 16),
        InkWell(
          onTap: () => showLevelsSheet(context),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.flag, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${level.label}${filterOn ? ' · filtered' : ''}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              Text('${formatHours(filtered)} / ${level.hours} h  (${(levelPct * 100).toStringAsFixed(2)}%)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: levelPct.clamp(0, 1).toDouble(),
                minHeight: 8,
                color: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _editDailyGoal(BuildContext context) async {
    final store = context.read<StudyStore>();
    final v = await promptText(context,
        title: 'Daily goal (minutes)',
        initial: store.settings.dailyGoalMinutes.toString(),
        keyboard: TextInputType.number);
    final n = int.tryParse(v ?? '');
    if (n != null && n > 0) store.updateSettings((s) => s.dailyGoalMinutes = n);
  }
}

class _ActiveTimerBanner extends StatelessWidget {
  final VoidCallback onOpenFocus;
  const _ActiveTimerBanner({required this.onOpenFocus});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final p = store.pomodoro;
    final t = store.activeTimer;
    final sub = store.subjectById(p?.subjectId ?? t?.subjectId);
    if (sub == null) return const SizedBox.shrink();
    final ch = sub.chapterById(p?.chapterId ?? t?.chapterId);
    final String label;
    final String clock;
    if (p != null) {
      label = p.isBreak ? '☕ Break' : (p.isPaused ? '⏸ Paused' : '🍅 Pomodoro');
      clock = formatShortClock(store.pomodoroRemainingMs);
    } else {
      label = 'Studying';
      clock = formatClock(store.liveMs);
    }
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onOpenFocus,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            SubjectAvatar(sub),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 12, color: sub.colorValue, fontWeight: FontWeight.w700)),
                Text(ch == null ? sub.name : '${sub.name} · ${ch.name}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
            Text(clock,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(width: 8),
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              icon: const Icon(Icons.stop_rounded),
              onPressed: store.stopTimer,
            ),
          ]),
        ),
      ),
    );
  }
}

class SubjectCard extends StatefulWidget {
  final Subject subject;
  const SubjectCard({super.key, required this.subject});

  @override
  State<SubjectCard> createState() => _SubjectCardState();
}

class _SubjectCardState extends State<SubjectCard> {
  bool _expanded = false;
  final _chapterCtrl = TextEditingController();

  @override
  void dispose() {
    _chapterCtrl.dispose();
    super.dispose();
  }

  void _addChapter() {
    final t = _chapterCtrl.text.trim();
    if (t.isEmpty) return;
    context.read<StudyStore>().addChapter(widget.subject.id, t);
    _chapterCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final s = widget.subject;
    final scheme = Theme.of(context).colorScheme;
    final total = store.subjectTotalMs(s.id);
    final today = store.subjectTodayMs(s.id);
    final progress = s.targetHours <= 0 ? 0.0 : total / 3600000 / s.targetHours;
    final subjectRunning = store.isRunning(s.id) && store.activeTimer!.chapterId == null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          onLongPress: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => SubjectDetailScreen(subjectId: s.id))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
            child: Column(children: [
              Row(children: [
                SubjectAvatar(s),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (s.category.isNotEmpty) s.category,
                        '${formatHours(total)} / ${s.targetHours.toStringAsFixed(s.targetHours % 1 == 0 ? 0 : 1)} h',
                        if (s.chapters.isNotEmpty) '${s.completedChapters}/${s.chapters.length} ch',
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: s.colorValue.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(formatClock(today),
                      style: TextStyle(
                        color: s.colorValue,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ),
                IconButton(
                  tooltip: 'Details',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => SubjectDetailScreen(subjectId: s.id))),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: LinearBar(value: progress, color: s.colorValue, height: 7)),
                const SizedBox(width: 10),
                Text('${(progress * 100).toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: scheme.onSurfaceVariant),
              ]),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: !_expanded
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  child: Column(children: [
                    const Divider(height: 1),
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.all_inclusive, color: s.colorValue),
                      title: const Text('General study (no chapter)'),
                      trailing: _PlayButton(
                        running: subjectRunning,
                        color: s.colorValue,
                        onTap: () => store.toggleTimer(s.id),
                      ),
                    ),
                    for (var i = 0; i < s.chapters.length; i++)
                      _ChapterRow(subject: s, chapter: s.chapters[i], index: i),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      child: TextField(
                        controller: _chapterCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _addChapter(),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Add chapter…',
                          suffixIcon: IconButton(icon: const Icon(Icons.add_circle), onPressed: _addChapter),
                        ),
                      ),
                    ),
                  ]),
                ),
        ),
      ]),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool running;
  final Color color;
  final VoidCallback onTap;
  const _PlayButton({required this.running, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: running ? Theme.of(context).colorScheme.error : color,
        boxShadow: running
            ? [BoxShadow(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4), blurRadius: 10)]
            : null,
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(running ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  final Subject subject;
  final Chapter chapter;
  final int index;
  const _ChapterRow({required this.subject, required this.chapter, required this.index});

  Future<void> _options(BuildContext context) async {
    final store = context.read<StudyStore>();
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(chapter.name, style: const TextStyle(fontWeight: FontWeight.w800))),
          ListTile(leading: const Icon(Icons.edit), title: const Text('Rename'), onTap: () => Navigator.pop(ctx, 'rename')),
          ListTile(
            leading: Icon(chapter.hidden ? Icons.visibility : Icons.visibility_off),
            title: Text(chapter.hidden ? 'Show time' : 'Hide time'),
            onTap: () => Navigator.pop(ctx, 'hide'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
            title: const Text('Delete chapter'),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'rename':
        final n = await promptText(context, title: 'Rename chapter', initial: chapter.name);
        if (n != null && n.isNotEmpty) store.updateChapter(subject.id, chapter.id, (c) => c.name = n);
      case 'hide':
        store.updateChapter(subject.id, chapter.id, (c) => c.hidden = !c.hidden);
      case 'delete':
        if (await confirmDialog(context,
            title: 'Delete "${chapter.name}"?',
            message: 'Its study time stays counted in ${subject.name}.')) {
          store.deleteChapter(subject.id, chapter.id);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final running = store.isRunning(subject.id, chapter.id);
    final today = store.chapterTodayMs(chapter.id);
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onLongPress: () => _options(context),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: Row(children: [
          Checkbox(
            value: chapter.completed,
            activeColor: subject.colorValue,
            onChanged: (v) => store.updateChapter(subject.id, chapter.id, (c) => c.completed = v ?? false),
          ),
          Expanded(
            child: Text(
              chapter.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: running ? FontWeight.w800 : FontWeight.w500,
                decoration: chapter.completed ? TextDecoration.lineThrough : null,
                color: chapter.completed ? scheme.onSurfaceVariant : null,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => store.updateChapter(subject.id, chapter.id, (c) => c.hidden = !c.hidden),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                chapter.hidden ? '•••' : formatClock(today),
                style: TextStyle(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: running ? subject.colorValue : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          _PlayButton(
            running: running,
            color: subject.colorValue,
            onTap: () => store.toggleTimer(subject.id, chapter.id),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- sheets

void showLevelsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Consumer<StudyStore>(builder: (ctx, store, _) {
      Future<void> edit(LevelGoal? g) async {
        final label = await promptText(ctx, title: g == null ? 'New level' : 'Level name', initial: g?.label ?? '');
        if (label == null || label.isEmpty || !ctx.mounted) return;
        final hrs = await promptText(ctx,
            title: 'Target hours', initial: g?.hours.toString() ?? '', keyboard: TextInputType.number);
        final h = int.tryParse(hrs ?? '');
        if (h == null || h <= 0) return;
        if (g == null) {
          store.addGoal(label, h);
        } else {
          store.updateGoal(g.id, label, h);
        }
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 8),
              child: Text('Levels & goals', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            RadioGroup<String>(
              groupValue: store.settings.activeGoalId,
              onChanged: (v) => store.setActiveGoal(v!),
              child: Column(children: [
                for (final g in store.goals)
                  RadioListTile<String>(
                    value: g.id,
                    title: Text(g.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${g.hours} hours'),
                    secondary: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => edit(g)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: store.goals.length <= 1 ? null : () => store.deleteGoal(g.id),
                      ),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => edit(null),
                icon: const Icon(Icons.add),
                label: const Text('Add level'),
              ),
            ),
          ]),
        ),
      );
    }),
  );
}

void showFilterSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) => Consumer<StudyStore>(
      builder: (ctx, store, _) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          const Text('Count towards level', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const Text('Choose which subjects count towards your level goal.'),
          const SizedBox(height: 8),
          for (final s in store.subjects)
            CheckboxListTile(
              value: store.isInHomeFilter(s.id),
              onChanged: (_) => store.toggleHomeFilter(s.id),
              title: Text('${s.emoji}  ${s.name}'),
            ),
        ]),
      ),
    ),
  );
}

void showReorderSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Consumer<StudyStore>(
      builder: (ctx, store, _) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: Column(children: [
          const Text('Drag to reorder', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: store.subjects.length,
              onReorder: store.reorderSubjects,
              itemBuilder: (_, i) {
                final s = store.subjects[i];
                return ListTile(
                  key: ValueKey(s.id),
                  leading: SubjectAvatar(s, size: 36),
                  title: Text(s.name),
                  trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                );
              },
            ),
          ),
        ]),
      ),
    ),
  );
}
