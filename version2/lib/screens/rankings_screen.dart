import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/day_utils.dart';
import '../models/models.dart';
import '../state/study_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'analytics_screen.dart';
import 'subject_detail_screen.dart';

enum RankMode { subjects, categories, chapters }

enum RankPeriod { allTime, week, today }

class RankingsScreen extends StatefulWidget {
  const RankingsScreen({super.key});

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  RankMode _mode = RankMode.subjects;
  RankPeriod _period = RankPeriod.allTime;

  Color _rankColor(BuildContext context, int i) => switch (i) {
        0 => gold,
        1 => silver,
        2 => bronze,
        _ => Theme.of(context).colorScheme.onSurfaceVariant,
      };

  int _subjectMs(StudyStore store, String id) {
    switch (_period) {
      case RankPeriod.allTime:
        return store.subjectTotalMs(id);
      case RankPeriod.today:
        return store.subjectTodayMs(id);
      case RankPeriod.week:
        var s = 0;
        for (var i = 0; i < 7; i++) {
          s += store.subjectDayMs(id, addDays(store.todayKey, -i));
        }
        return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final scheme = Theme.of(context).colorScheme;

    final rows = <_RankRow>[];
    switch (_mode) {
      case RankMode.subjects:
        for (final s in store.subjects) {
          final ms = _subjectMs(store, s.id);
          rows.add(_RankRow(
            leading: SubjectAvatar(s, size: 40),
            title: s.name,
            subtitle: s.category.isEmpty ? 'Uncategorized' : s.category,
            ms: ms,
            progress: _period == RankPeriod.allTime ? ms / 3600000 / s.targetHours : null,
            color: s.colorValue,
            medals: store.medalsFor(s.id),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubjectDetailScreen(subjectId: s.id))),
          ));
        }
      case RankMode.categories:
        final map = <String, ({int ms, int count, double target})>{};
        for (final s in store.subjects) {
          final c = s.category.isEmpty ? 'Uncategorized' : s.category;
          final prev = map[c] ?? (ms: 0, count: 0, target: 0.0);
          map[c] = (ms: prev.ms + _subjectMs(store, s.id), count: prev.count + 1, target: prev.target + s.targetHours);
        }
        map.forEach((name, v) {
          rows.add(_RankRow(
            leading: CircleAvatar(child: Text(name.characters.first.toUpperCase())),
            title: name,
            subtitle: '${v.count} subject${v.count == 1 ? '' : 's'}',
            ms: v.ms,
            progress: _period == RankPeriod.allTime && v.target > 0 ? v.ms / 3600000 / v.target : null,
            color: scheme.primary,
          ));
        });
      case RankMode.chapters:
        for (final s in store.subjects) {
          for (final c in s.chapters) {
            final ms = _period == RankPeriod.allTime
                ? store.chapterTotalMs(c.id)
                : (_period == RankPeriod.today ? store.chapterTodayMs(c.id) : _chapterWeek(store, c.id));
            rows.add(_RankRow(
              leading: SubjectAvatar(s, size: 40),
              title: c.name,
              subtitle: s.name,
              ms: ms,
              color: s.colorValue,
            ));
          }
        }
    }
    rows.sort((a, b) => b.ms.compareTo(a.ms));
    final visible = rows.where((r) => r.ms > 0 || _period == RankPeriod.allTime).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonalIcon(
              onPressed: () => _showHallOfFame(context),
              icon: const Icon(Icons.emoji_events, size: 18),
              label: const Text('Hall of Fame'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          SegmentedButton<RankMode>(
            segments: const [
              ButtonSegment(value: RankMode.subjects, label: Text('Subjects')),
              ButtonSegment(value: RankMode.categories, label: Text('Categories')),
              ButtonSegment(value: RankMode.chapters, label: Text('Chapters')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final p in RankPeriod.values)
              ChoiceChip(
                label: Text(switch (p) {
                  RankPeriod.allTime => 'All time',
                  RankPeriod.week => 'This week',
                  RankPeriod.today => 'Today',
                }),
                selected: _period == p,
                onSelected: (_) => setState(() => _period = p),
              ),
          ]),
          if (_mode == RankMode.subjects)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text('🏅 Each finished day, the top 3 subjects earn gold, silver and bronze medals.',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            const EmptyState(emoji: '🏁', title: 'No rankings yet', body: 'Study a bit and the leaderboard will fill up.')
          else ...[
            if (visible.length >= 3) _Podium(rows: visible.take(3).toList()),
            for (var i = 0; i < visible.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: visible[i].onTap,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        SizedBox(
                          width: 36,
                          child: Text('#${i + 1}',
                              style: TextStyle(
                                  fontSize: i < 3 ? 20 : 15, fontWeight: FontWeight.w900, color: _rankColor(context, i))),
                        ),
                        visible[i].leading,
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(visible[i].title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            Text(visible[i].subtitle,
                                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                            if (visible[i].medals != null && visible[i].medals!.total > 0) ...[
                              const SizedBox(height: 4),
                              MedalPills(visible[i].medals!),
                            ],
                            if (visible[i].progress != null) ...[
                              const SizedBox(height: 6),
                              LinearBar(
                                  value: visible[i].progress!,
                                  color: i < 3 ? _rankColor(context, i) : visible[i].color,
                                  height: 5),
                            ],
                          ]),
                        ),
                        const SizedBox(width: 10),
                        Text('${formatHours(visible[i].ms)}h',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                      ]),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  int _chapterWeek(StudyStore store, String chapterId) {
    final startKey = addDays(store.todayKey, -6);
    var sum = 0;
    for (final s in store.sessions) {
      if (s.chapterId != chapterId) continue;
      splitByDay(s.startMs, s.endMs, store.settings.dayStartHour).forEach((k, v) {
        if (k.compareTo(startKey) >= 0) sum += v;
      });
    }
    if (store.activeTimer?.chapterId == chapterId) sum += store.liveMs;
    return sum;
  }

  void _showHallOfFame(BuildContext context) {
    final store = context.read<StudyStore>();
    final daily = store.dailyWithLive;
    final days = daily.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    // Best 7-day window.
    var bestWeekMs = 0;
    String? bestWeekEnd;
    for (final k in daily.keys) {
      var s = 0;
      for (var i = 0; i < 7; i++) {
        s += daily[addDays(k, -i)] ?? 0;
      }
      if (s > bestWeekMs) {
        bestWeekMs = s;
        bestWeekEnd = k;
      }
    }
    final streak = store.streak;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          const Text('🏆 Hall of Fame', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: StatTile(
                    label: 'Longest streak', value: '${streak.longest} days', icon: Icons.local_fire_department, color: Colors.orange)),
            const SizedBox(width: 10),
            Expanded(
                child: StatTile(
                    label: bestWeekEnd == null
                        ? 'Best 7 days'
                        : 'Best 7 days (to ${DateFormat('d MMM').format(dateOfKey(bestWeekEnd))})',
                    value: formatDuration(bestWeekMs),
                    icon: Icons.date_range,
                    color: Colors.purple)),
          ]),
          const SectionTitle('Best days'),
          if (days.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text('Start studying to set a record!', textAlign: TextAlign.center)),
          for (var i = 0; i < days.length && i < 5; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => showDayBreakdown(context, days[i].key),
                leading: Icon(Icons.military_tech, size: 32, color: _rankColor(ctx, i)),
                title: Text(prettyDayKey(days[i].key, store.todayKey), style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(i == 0 ? 'ALL-TIME RECORD' : 'Rank #${i + 1}',
                    style: TextStyle(color: _rankColor(ctx, i), fontWeight: FontWeight.w700)),
                trailing: Text(formatDuration(days[i].value),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ),
            ),
        ]),
      ),
    );
  }
}

class _RankRow {
  final Widget leading;
  final String title;
  final String subtitle;
  final int ms;
  final double? progress;
  final Color color;
  final Medals? medals;
  final VoidCallback? onTap;
  _RankRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.ms,
    required this.color,
    this.progress,
    this.medals,
    this.onTap,
  });
}

class _Podium extends StatelessWidget {
  final List<_RankRow> rows;
  const _Podium({required this.rows});

  @override
  Widget build(BuildContext context) {
    Widget block(_RankRow r, double h, Color c, String medal) => Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text(medal, style: const TextStyle(fontSize: 26)),
            Text(r.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            Text('${formatHours(r.ms)}h', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Container(
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [c, c.withValues(alpha: 0.5)],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
            ),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        height: 170,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          block(rows[1], 60, silver, '🥈'),
          block(rows[0], 90, gold, '🥇'),
          block(rows[2], 40, bronze, '🥉'),
        ]),
      ),
    );
  }
}
