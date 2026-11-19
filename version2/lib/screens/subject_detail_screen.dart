import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/day_utils.dart';
import '../state/study_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/subject_form.dart';
import 'session_log_screen.dart';

class SubjectDetailScreen extends StatefulWidget {
  final String subjectId;
  const SubjectDetailScreen({super.key, required this.subjectId});

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  late final TextEditingController _note;
  bool _noteDirty = false;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: context.read<StudyStore>().subjectById(widget.subjectId)?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final s = store.subjectById(widget.subjectId);
    if (s == null) return const Scaffold(body: Center(child: Text('Subject deleted')));
    final scheme = Theme.of(context).colorScheme;
    final total = store.subjectTotalMs(s.id);
    var week = 0;
    for (var i = 0; i < 7; i++) {
      week += store.subjectDayMs(s.id, addDays(store.todayKey, -i));
    }
    final medals = store.medalsFor(s.id);
    final chapterTotals = s.chapters.map((c) => (chapter: c, ms: store.chapterTotalMs(c.id))).toList()
      ..sort((a, b) => b.ms.compareTo(a.ms));
    final chapterSum = chapterTotals.fold<int>(0, (a, e) => a + e.ms);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.name),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => showSubjectForm(context, existing: s)),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirmDialog(context,
                  title: 'Delete ${s.name}?',
                  message: 'This removes the subject, its chapters and all of its sessions. This cannot be undone.')) {
                store.deleteSubject(s.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                ProgressRing(
                  progress: total / 3600000 / s.targetHours,
                  color: s.colorValue,
                  size: 96,
                  child: Text(s.emoji, style: const TextStyle(fontSize: 34)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${formatHours(total)} h',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                    Text('of ${s.targetHours.toStringAsFixed(0)} h target '
                        '(${(total / 3600000 / s.targetHours * 100).toStringAsFixed(1)}%)',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                    if (s.category.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Chip(label: Text(s.category), visualDensity: VisualDensity.compact),
                    ],
                    if (medals.total > 0) ...[const SizedBox(height: 6), MedalPills(medals)],
                  ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: StatTile(
                    label: 'Today', value: formatDuration(store.subjectTodayMs(s.id)), icon: Icons.today, color: s.colorValue)),
            const SizedBox(width: 10),
            Expanded(child: StatTile(label: 'Last 7 days', value: formatDuration(week), icon: Icons.date_range, color: s.colorValue)),
            const SizedBox(width: 10),
            Expanded(
                child: StatTile(
                    label: 'Syllabus',
                    value: s.chapters.isEmpty ? '—' : '${(s.completedChapters / s.chapters.length * 100).round()}%',
                    icon: Icons.checklist,
                    color: s.colorValue)),
          ]),
          const SectionTitle('Last 14 days'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
              child: SizedBox(height: 170, child: _SubjectBars(subjectId: s.id, color: s.colorValue)),
            ),
          ),
          SectionTitle('Chapter ranking',
              trailing: TextButton.icon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => SessionLogScreen(subjectId: s.id))),
                icon: const Icon(Icons.history, size: 18),
                label: const Text('Sessions'),
              )),
          Card(
            child: chapterTotals.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No chapters yet. Add some from the Today tab.', textAlign: TextAlign.center),
                  )
                : Column(children: [
                    for (var i = 0; i < chapterTotals.length; i++)
                      ListTile(
                        leading: SizedBox(
                          width: 30,
                          child: Text(i < 3 ? ['🥇', '🥈', '🥉'][i] : '#${i + 1}',
                              style: TextStyle(fontSize: i < 3 ? 20 : 14, fontWeight: FontWeight.w800)),
                        ),
                        title: Text(chapterTotals[i].chapter.name,
                            style: TextStyle(
                                decoration: chapterTotals[i].chapter.completed ? TextDecoration.lineThrough : null)),
                        subtitle: LinearBar(
                          value: chapterSum == 0 ? 0 : chapterTotals[i].ms / chapterSum,
                          color: i == 0 ? gold : s.colorValue,
                          height: 5,
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${formatHours(chapterTotals[i].ms, decimals: 2)} h',
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(
                                chapterSum == 0
                                    ? '0%'
                                    : '${(chapterTotals[i].ms / chapterSum * 100).toStringAsFixed(1)}%',
                                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                  ]),
          ),
          SectionTitle('Notes',
              trailing: _noteDirty
                  ? FilledButton.tonal(
                      onPressed: () {
                        store.updateSubject(s.id, (x) => x.note = _note.text);
                        setState(() => _noteDirty = false);
                        FocusScope.of(context).unfocus();
                        showSnack(context, 'Note saved');
                      },
                      child: const Text('Save'),
                    )
                  : null),
          TextField(
            controller: _note,
            minLines: 4,
            maxLines: 12,
            onChanged: (_) {
              if (!_noteDirty) setState(() => _noteDirty = true);
            },
            decoration: const InputDecoration(hintText: 'Syllabus, deadlines, important formulas…'),
          ),
        ],
      ),
    );
  }
}

class _SubjectBars extends StatelessWidget {
  final String subjectId;
  final Color color;
  const _SubjectBars({required this.subjectId, required this.color});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final today = store.todayKey;
    final values = <double>[];
    final labels = <String>[];
    for (var i = 13; i >= 0; i--) {
      final k = addDays(today, -i);
      values.add(store.subjectDayMs(subjectId, k) / 3600000);
      labels.add(DateFormat('d').format(dateOfKey(k)));
    }
    final maxY = values.fold<double>(0, (a, b) => b > a ? b : a);
    return BarChart(BarChartData(
      maxY: maxY <= 0 ? 1 : maxY * 1.2,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (g, _, rod, _) =>
              BarTooltipItem(formatDuration((rod.toY * 3600000).round()), const TextStyle(color: Colors.white)),
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            getTitlesWidget: (v, m) => Text('${v.toStringAsFixed(v < 2 ? 1 : 0)}h', style: const TextStyle(fontSize: 9)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, m) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(labels[v.toInt()], style: const TextStyle(fontSize: 9)),
            ),
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < values.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: values[i],
              width: 12,
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ]),
      ],
    ));
  }
}
