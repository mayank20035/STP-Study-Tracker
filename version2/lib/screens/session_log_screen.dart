import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/day_utils.dart';
import '../models/models.dart';
import '../state/study_store.dart';
import '../widgets/common.dart';

/// Every recorded session grouped by study day. Sessions can be edited,
/// deleted (with undo) or added manually.
class SessionLogScreen extends StatelessWidget {
  final String? subjectId;
  const SessionLogScreen({super.key, this.subjectId});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final subject = store.subjectById(subjectId);
    final list = store.sessions
        .where((s) => subjectId == null || s.subjectId == subjectId)
        .toList()
      ..sort((a, b) => b.startMs.compareTo(a.startMs));
    final groups = <String, List<StudySession>>{};
    for (final s in list) {
      groups.putIfAbsent(dayKeyForMs(s.startMs, store.settings.dayStartHour), () => []).add(s);
    }
    final keys = groups.keys.toList();

    return Scaffold(
      appBar: AppBar(title: Text(subject == null ? 'Session log' : '${subject.name} sessions')),
      floatingActionButton: store.subjects.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showSessionEditor(context, presetSubjectId: subjectId),
              icon: const Icon(Icons.add),
              label: const Text('Add manually'),
            ),
      body: list.isEmpty
          ? const Center(
              child: EmptyState(
                emoji: '🗒️',
                title: 'No sessions yet',
                body: 'Start a timer, or add a session you forgot to track.',
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              itemCount: keys.length,
              itemBuilder: (context, i) {
                final key = keys[i];
                final items = groups[key]!;
                final total = items.fold<int>(0, (a, s) => a + s.durationMs);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(prettyDayKey(key, store.todayKey),
                        trailing: Text(formatDuration(total),
                            style: TextStyle(
                                fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary))),
                    Card(
                      child: Column(children: [
                        for (final s in items) _SessionTile(session: s),
                      ]),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final StudySession session;
  const _SessionTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final store = context.read<StudyStore>();
    final sub = store.subjectById(session.subjectId);
    if (sub == null) return const SizedBox.shrink();
    final ch = sub.chapterById(session.chapterId);
    final tf = DateFormat('h:mm a');
    final tags = [
      if (session.pomodoro) '🍅',
      if (session.manual) '✍️',
    ].join(' ');
    return Dismissible(
      key: ValueKey(session.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Theme.of(context).colorScheme.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        final copy = session;
        store.deleteSession(session.id);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: const Text('Session deleted'),
            action: SnackBarAction(label: 'Undo', onPressed: () => store.addSession(copy)),
          ));
      },
      child: ListTile(
        leading: SubjectAvatar(sub, size: 38),
        title: Text(ch == null ? sub.name : '${sub.name} · ${ch.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(session.manual && session.id.startsWith('v1_')
            ? 'Imported from v1'
            : '${tf.format(session.start)} – ${tf.format(session.end)} $tags'),
        trailing: Text(formatDuration(session.durationMs), style: const TextStyle(fontWeight: FontWeight.w700)),
        onTap: () => showSessionEditor(context, existing: session),
      ),
    );
  }
}

/// Add a forgotten session or edit an existing one.
Future<void> showSessionEditor(BuildContext context, {StudySession? existing, String? presetSubjectId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SessionEditor(existing: existing, presetSubjectId: presetSubjectId),
  );
}

class _SessionEditor extends StatefulWidget {
  final StudySession? existing;
  final String? presetSubjectId;
  const _SessionEditor({this.existing, this.presetSubjectId});

  @override
  State<_SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<_SessionEditor> {
  late String _subjectId;
  String? _chapterId;
  late DateTime _start;
  late int _minutes;

  @override
  void initState() {
    super.initState();
    final store = context.read<StudyStore>();
    final e = widget.existing;
    _subjectId = e?.subjectId ?? widget.presetSubjectId ?? store.subjects.first.id;
    _chapterId = e?.chapterId;
    _minutes = e == null ? 60 : (e.durationMs / 60000).round().clamp(1, 24 * 60);
    final now = DateTime.now();
    _start = e?.start ?? now.subtract(Duration(minutes: _minutes));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final sub = store.subjectById(_subjectId) ?? store.subjects.first;
    if (sub.chapterById(_chapterId) == null) _chapterId = null;
    final end = _start.add(Duration(minutes: _minutes));
    final df = DateFormat('EEE, d MMM yyyy');
    final tf = DateFormat('h:mm a');

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? 'Add session' : 'Edit session',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: sub.id,
              decoration: const InputDecoration(labelText: 'Subject'),
              items: [
                for (final s in store.subjects)
                  DropdownMenuItem(value: s.id, child: Text('${s.emoji}  ${s.name}')),
              ],
              onChanged: (v) => setState(() {
                _subjectId = v!;
                _chapterId = null;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey('ch_${sub.id}'),
              initialValue: _chapterId,
              decoration: const InputDecoration(labelText: 'Chapter (optional)'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('— Whole subject —')),
                for (final c in sub.chapters) DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _chapterId = v),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(df.format(_start)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _start,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) {
                      setState(() => _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(tf.format(_start)),
                onPressed: () async {
                  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
                  if (t != null) {
                    setState(() => _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute));
                  }
                },
              ),
            ]),
            const SizedBox(height: 16),
            Text('Duration: ${formatDuration(_minutes * 60000)}  (ends ${tf.format(end)})',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Slider(
              value: _minutes.toDouble().clamp(5, 720),
              min: 5,
              max: 720,
              divisions: 143,
              label: formatDuration(_minutes * 60000),
              onChanged: (v) => setState(() => _minutes = v.round()),
            ),
            Wrap(spacing: 8, children: [
              for (final m in [15, 30, 45, 60, 90, 120, 180])
                ActionChip(label: Text(formatDuration(m * 60000)), onPressed: () => setState(() => _minutes = m)),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              if (widget.existing != null)
                IconButton.filledTonal(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    store.deleteSession(widget.existing!.id);
                    Navigator.pop(context);
                  },
                ),
              if (widget.existing != null) const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  icon: const Icon(Icons.check),
                  label: const Text('Save session'),
                  onPressed: () {
                    if (end.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
                      showSnack(context, 'A session cannot end in the future');
                      return;
                    }
                    final s = StudySession(
                      id: widget.existing?.id ?? newId(),
                      subjectId: _subjectId,
                      chapterId: _chapterId,
                      startMs: _start.millisecondsSinceEpoch,
                      endMs: end.millisecondsSinceEpoch,
                      manual: widget.existing?.manual ?? true,
                      pomodoro: widget.existing?.pomodoro ?? false,
                    );
                    if (widget.existing == null) {
                      store.addSession(s);
                    } else {
                      store.replaceSession(s);
                    }
                    Navigator.pop(context);
                  },
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
