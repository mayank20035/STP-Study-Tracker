import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/study_store.dart';
import 'common.dart';

/// Bottom sheet used to create or edit a subject.
Future<void> showSubjectForm(BuildContext context, {Subject? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SubjectForm(existing: existing),
  );
}

class _SubjectForm extends StatefulWidget {
  final Subject? existing;
  const _SubjectForm({this.existing});

  @override
  State<_SubjectForm> createState() => _SubjectFormState();
}

class _SubjectFormState extends State<_SubjectForm> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  late String _emoji;
  late int _color;
  late String _category;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final count = context.read<StudyStore>().subjects.length;
    _name = TextEditingController(text: e?.name ?? '');
    _target = TextEditingController(text: e == null ? '' : _fmt(e.targetHours));
    _emoji = e?.emoji ?? subjectEmojis[count % subjectEmojis.length];
    _color = e?.color ?? subjectPalette[count % subjectPalette.length];
    _category = e?.category ?? '';
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void _save() {
    final store = context.read<StudyStore>();
    final name = _name.text.trim();
    final targetText = _target.text.trim();
    final missing = [
      if (name.isEmpty) 'Subject name',
      if (targetText.isEmpty) 'Target hours',
    ];
    if (missing.isNotEmpty) {
      showFillFieldsDialog(context, missingFieldsMessage(missing));
      return;
    }
    final target = double.tryParse(targetText);
    if (target == null || target <= 0) {
      showFillFieldsDialog(context, 'Target hours must be a number above 0.');
      return;
    }
    if (widget.existing == null) {
      store.addSubject(name: name, targetHours: target, emoji: _emoji, color: _color, category: _category);
    } else {
      store.updateSubject(widget.existing!.id, (s) {
        s.name = name;
        s.targetHours = target;
        s.emoji = _emoji;
        s.color = _color;
        s.category = _category;
      });
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? 'New subject' : 'Edit subject',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Color(_color).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(_emoji, style: const TextStyle(fontSize: 28)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: widget.existing == null,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Subject name'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _target,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Target hours', suffixText: 'h'),
            ),
            const SizedBox(height: 16),
            const Text('Icon', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in subjectEmojis)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _emoji = e),
                    child: Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: e == _emoji ? scheme.primaryContainer : Colors.transparent,
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Colour', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in subjectPalette)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: c == _color ? scheme.onSurface : Colors.transparent, width: 3),
                      ),
                      child: c == _color ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Category', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('None'),
                  selected: _category.isEmpty,
                  onSelected: (_) => setState(() => _category = ''),
                ),
                for (final c in store.categories)
                  ChoiceChip(
                    label: Text(c),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('New'),
                  onPressed: () async {
                    final n = await promptText(context, title: 'New category', hint: 'e.g. Exam Prep');
                    if (n != null && n.isNotEmpty) {
                      store.addCategory(n);
                      setState(() => _category = n);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: Text(widget.existing == null ? 'Create subject' : 'Save changes'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
