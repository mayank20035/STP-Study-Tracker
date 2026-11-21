import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../logic/day_utils.dart';
import '../logic/stats.dart';
import '../models/models.dart';
import '../services/backup_codec.dart';
import '../state/study_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'focus_screen.dart';
import 'session_log_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final scheme = Theme.of(context).colorScheme;
    final p = store.profile;
    final xp = store.xp;
    final level = store.level;
    final cur = xpForLevel(level);
    final next = xpForLevel(level + 1);
    final streak = store.streak;
    final ach = store.achievements;
    final unlocked = ach.where((a) => a.unlocked).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                GestureDetector(
                  onTap: () => _pickAvatar(context),
                  child: Stack(children: [
                    CircleAvatar(
                      radius: 46,
                      backgroundColor: scheme.primaryContainer,
                      child: Text(p.avatar, style: const TextStyle(fontSize: 46)),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: scheme.primary,
                        child: const Icon(Icons.edit, size: 14, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () async {
                    final n = await promptText(context, title: 'Your name', initial: p.name);
                    if (n != null && n.isNotEmpty) store.updateProfile((x) => x.name = n);
                  },
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(p.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                    Icon(Icons.edit, size: 16, color: scheme.onSurfaceVariant),
                  ]),
                ),
                Text('Level $level · ${titleForLevel(level)}',
                    style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                LinearBar(value: next == cur ? 1 : (xp - cur) / (next - cur), color: scheme.primary, height: 10),
                const SizedBox(height: 4),
                Text('$xp XP · ${next - xp} XP to level ${level + 1}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.4,
            children: [
              StatTile(label: 'Total studied', value: '${formatHours(store.totalMs)} h', icon: Icons.hourglass_bottom),
              StatTile(
                  label: 'Current streak',
                  value: '${streak.current} 🔥',
                  icon: Icons.local_fire_department,
                  color: Colors.orange),
              StatTile(
                  label: 'Sessions', value: '${store.snapshot.sessionCount}', icon: Icons.history, color: Colors.teal),
              StatTile(
                  label: 'Pomodoros', value: '${store.pomodorosCompleted} 🍅', icon: Icons.timer, color: Colors.red),
            ],
          ),
          SectionTitle('Achievements', trailing: Text('$unlocked / ${ach.length}')),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.8,
            ),
            itemCount: ach.length,
            itemBuilder: (_, i) {
              final a = ach[i];
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('${a.achievement.emoji}  ${a.achievement.title}'),
                    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.achievement.description),
                      const SizedBox(height: 12),
                      LinearBar(value: a.progress, color: a.unlocked ? gold : scheme.primary),
                      const SizedBox(height: 4),
                      Text(a.unlocked ? 'Unlocked!' : '${(a.progress * 100).floor()}% complete'),
                    ]),
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: a.unlocked ? gold.withValues(alpha: 0.15) : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    border: Border.all(color: a.unlocked ? gold : Colors.transparent),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Opacity(
                      opacity: a.unlocked ? 1 : 0.3,
                      child: Text(a.achievement.emoji, style: const TextStyle(fontSize: 28)),
                    ),
                    const SizedBox(height: 4),
                    Text(a.achievement.title,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, fontWeight: a.unlocked ? FontWeight.w800 : FontWeight.w500)),
                    if (!a.unlocked) ...[
                      const SizedBox(height: 4),
                      LinearBar(value: a.progress, color: scheme.primary, height: 3),
                    ],
                  ]),
                ),
              );
            },
          ),
          SectionTitle('My traits',
              trailing: TextButton(onPressed: () => _editTraits(context), child: const Text('Edit'))),
          if (p.traits.isEmpty)
            Text('No traits selected. Tap Edit.', style: TextStyle(color: scheme.onSurfaceVariant))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [for (final t in p.traits) Chip(label: Text(t))]),
          const SectionTitle('Appearance'),
          Card(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Light')),
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Auto')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
                  ],
                  selected: {store.settings.themeMode},
                  onSelectionChanged: (s) => store.updateSettings((x) => x.themeMode = s.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  for (var i = 0; i < accentColors.length; i++)
                    Tooltip(
                      message: accentNames[i],
                      child: GestureDetector(
                        onTap: () => store.updateSettings((x) => x.accentIndex = i),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: accentColors[i],
                          child: store.settings.accentIndex == i
                              ? const Icon(Icons.check, color: Colors.white, size: 18)
                              : null,
                        ),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          const SectionTitle('Study settings'),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Daily goal'),
                trailing: Text(formatDuration(store.settings.dailyGoalMinutes * 60000),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () async {
                  final v = await promptText(context,
                      title: 'Daily goal (minutes)',
                      initial: '${store.settings.dailyGoalMinutes}',
                      keyboard: TextInputType.number,
                      validate: positiveWholeNumber);
                  final n = int.tryParse(v ?? '');
                  if (n != null && n > 0) store.updateSettings((s) => s.dailyGoalMinutes = n);
                },
              ),
              ListTile(
                leading: const Icon(Icons.local_fire_department_outlined),
                title: const Text('Minimum for streak'),
                subtitle: const Text('Study at least this much for a day to count'),
                trailing: DropdownButton<int>(
                  value: store.settings.streakMinMinutes,
                  underline: const SizedBox(),
                  items: [
                    for (final m in [1, 15, 30, 60, 120])
                      DropdownMenuItem(value: m, child: Text(formatDuration(m * 60000))),
                  ],
                  onChanged: (v) => store.updateSettings((s) => s.streakMinMinutes = v!),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.nightlight_outlined),
                title: const Text('New day starts at'),
                subtitle: const Text('Late-night study counts for the previous day'),
                trailing: DropdownButton<int>(
                  value: store.settings.dayStartHour,
                  underline: const SizedBox(),
                  items: [
                    for (var h = 0; h <= 6; h++) DropdownMenuItem(value: h, child: Text(h == 0 ? 'Midnight' : '$h AM')),
                  ],
                  onChanged: (v) => store.updateSettings((s) => s.dayStartHour = v!),
                ),
              ),
              ListTile(
                leading: const Text('🍅', style: TextStyle(fontSize: 20)),
                title: const Text('Pomodoro'),
                subtitle: Text('${store.settings.pomodoroWorkMin} / ${store.settings.pomodoroShortBreakMin} / '
                    '${store.settings.pomodoroLongBreakMin} min'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showPomodoroSettings(context),
              ),
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('Categories'),
                subtitle: Text(store.categories.join(', ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _manageCategories(context),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Session log'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SessionLogScreen())),
              ),
            ]),
          ),
          const SectionTitle('Data & backup'),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.upload_file, color: Colors.blue),
                title: const Text('Export backup'),
                subtitle: const Text('Save or share a .json file'),
                onTap: () async {
                  try {
                    await store.exportBackup();
                  } catch (e) {
                    if (context.mounted) showSnack(context, 'Export failed: $e');
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.download, color: Colors.amber),
                title: const Text('Import backup'),
                subtitle: const Text('Works with v2 and old v1 STP backups'),
                onTap: () => _import(context),
              ),
              ListTile(
                leading: Icon(Icons.delete_forever, color: scheme.error),
                title: Text('Reset all data', style: TextStyle(color: scheme.error)),
                onTap: () async {
                  if (await confirmDialog(context,
                      title: 'Reset everything?',
                      message: 'All subjects, sessions, achievements and settings will be deleted. '
                          'Export a backup first if you want to keep them.',
                      confirm: 'Reset')) {
                    store.resetAll();
                    if (context.mounted) showSnack(context, 'All data cleared');
                  }
                },
              ),
            ]),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('STP v2.3.0 · Made with Flutter 💙',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    final store = context.read<StudyStore>();
    try {
      final data = await store.pickBackup();
      if (data == null || !context.mounted) return;
      final ok = await confirmDialog(
        context,
        title: 'Replace current data?',
        message: 'The backup contains ${data.subjects.length} subjects and ${data.sessions.length} sessions. '
            'Your current data will be replaced.',
        confirm: 'Import',
        destructive: false,
      );
      if (!ok) return;
      store.replaceAll(data);
      if (context.mounted) showSnack(context, 'Backup imported successfully 🎉');
    } on BackupFormatException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    } catch (e) {
      if (context.mounted) showSnack(context, 'Import failed: $e');
    }
  }

  void _pickAvatar(BuildContext context) {
    final store = context.read<StudyStore>();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in avatarOptions)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  store.updateProfile((p) => p.avatar = a);
                  Navigator.pop(ctx);
                },
                child: Padding(padding: const EdgeInsets.all(6), child: Text(a, style: const TextStyle(fontSize: 34))),
              ),
          ]),
        ),
      ),
    );
  }

  void _editTraits(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Consumer<StudyStore>(
        builder: (ctx, store, _) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in traitOptions)
                FilterChip(
                  label: Text(t),
                  selected: store.profile.traits.contains(t),
                  onSelected: (on) => store.updateProfile((p) => on ? p.traits.add(t) : p.traits.remove(t)),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  void _manageCategories(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Consumer<StudyStore>(
        builder: (ctx, store, _) => SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
            const Text('Categories', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            for (final c in store.categories)
              ListTile(
                title: Text(c),
                subtitle: Text('${store.subjects.where((s) => s.category == c).length} subjects'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final n = await promptText(ctx, title: 'Rename category', initial: c);
                      if (n != null) store.renameCategory(c, n);
                    },
                  ),
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => store.deleteCategory(c)),
                ]),
              ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () async {
                final n = await promptText(ctx, title: 'New category');
                if (n != null) store.addCategory(n);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add category'),
            ),
          ]),
        ),
      ),
    );
  }
}
