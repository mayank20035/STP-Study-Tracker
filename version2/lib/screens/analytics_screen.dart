import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/day_utils.dart';
import '../state/study_store.dart';
import '../widgets/common.dart';
import '../widgets/heatmap.dart';

enum Range { week, month, year }

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Range _range = Range.week;
  bool _calendarView = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final scheme = Theme.of(context).colorScheme;
    final daily = store.dailyWithLive;
    final today = store.todayKey;

    // ---- bar data
    final values = <double>[];
    final labels = <String>[];
    var rangeDays = 7;
    switch (_range) {
      case Range.week:
        for (var i = 6; i >= 0; i--) {
          final k = addDays(today, -i);
          values.add((daily[k] ?? 0) / 3600000);
          labels.add(DateFormat('E').format(dateOfKey(k)).substring(0, 2));
        }
      case Range.month:
        rangeDays = 30;
        for (var i = 29; i >= 0; i--) {
          final k = addDays(today, -i);
          values.add((daily[k] ?? 0) / 3600000);
          labels.add(i % 5 == 0 ? DateFormat('d').format(dateOfKey(k)) : '');
        }
      case Range.year:
        final t = dateOfKey(today);
        rangeDays = 0;
        for (var i = 11; i >= 0; i--) {
          final m = DateTime(t.year, t.month - i);
          final prefix = DateFormat('yyyy-MM').format(m);
          var sum = 0;
          daily.forEach((k, v) {
            if (k.startsWith(prefix)) sum += v;
          });
          values.add(sum / 3600000);
          labels.add(DateFormat('MMM').format(m).substring(0, 1));
        }
        final start = DateTime(t.year, t.month - 11, 1);
        rangeDays = dateOfKey(today).difference(start).inDays + 1;
    }

    // ---- range totals (daily granularity)
    var rangeTotal = 0;
    var bestDayMs = 0;
    String? bestDay;
    var activeDays = 0;
    final subjectRange = <String, int>{};
    for (var i = 0; i < rangeDays; i++) {
      final k = addDays(today, -i);
      final v = daily[k] ?? 0;
      rangeTotal += v;
      if (v > 0) activeDays++;
      if (v > bestDayMs) {
        bestDayMs = v;
        bestDay = k;
      }
      for (final s in store.subjects) {
        final sv = store.subjectDayMs(s.id, k);
        if (sv > 0) subjectRange[s.id] = (subjectRange[s.id] ?? 0) + sv;
      }
    }
    final avg = rangeDays == 0 ? 0 : rangeTotal ~/ rangeDays;
    final insights = store.insights;

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          SegmentedButton<Range>(
            segments: const [
              ButtonSegment(value: Range.week, label: Text('Week')),
              ButtonSegment(value: Range.month, label: Text('Month')),
              ButtonSegment(value: Range.year, label: Text('Year')),
            ],
            selected: {_range},
            onSelectionChanged: (s) => setState(() => _range = s.first),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: StatTile(label: 'Total', value: formatDuration(rangeTotal), icon: Icons.timer)),
            const SizedBox(width: 10),
            Expanded(
                child: StatTile(
                    label: 'Avg / day', value: formatDuration(avg), icon: Icons.show_chart, color: Colors.teal)),
            const SizedBox(width: 10),
            Expanded(
                child: StatTile(
                    label: 'Active days',
                    value: '$activeDays/$rangeDays',
                    icon: Icons.local_fire_department,
                    color: Colors.orange)),
          ]),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 12),
                  child: Text(
                    bestDay == null
                        ? 'No study time in this range yet'
                        : '🏆 Best day: ${DateFormat('d MMM').format(dateOfKey(bestDay))} · ${formatDuration(bestDayMs)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(height: 200, child: _Bars(values: values, labels: labels, color: scheme.primary)),
              ]),
            ),
          ),
          if (insights.isNotEmpty) ...[
            const SectionTitle('Smart insights'),
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: insights.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => SizedBox(
                  width: 230,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(insights[i].emoji, style: const TextStyle(fontSize: 24)),
                        const SizedBox(height: 4),
                        Text(insights[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(insights[i].body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ],
          SectionTitle('Consistency',
              trailing: TextButton.icon(
                onPressed: () => setState(() => _calendarView = !_calendarView),
                icon: Icon(_calendarView ? Icons.grid_on : Icons.calendar_month, size: 18),
                label: Text(_calendarView ? 'Heatmap' : 'Calendar'),
              )),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _calendarView
                  ? MonthCalendar(daily: daily, todayKey: today, onTap: (k) => showDayBreakdown(context, k))
                  : Column(children: [
                      YearHeatmap(daily: daily, todayKey: today, weeks: 26, onTap: (k) => showDayBreakdown(context, k)),
                      const SizedBox(height: 8),
                      const HeatLegend(),
                    ]),
            ),
          ),
          if (subjectRange.isNotEmpty) ...[
            const SectionTitle('Subject split'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: PieChart(PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 36,
                      sections: [
                        for (final e in subjectRange.entries)
                          PieChartSectionData(
                            value: e.value.toDouble(),
                            color: store.subjectById(e.key)?.colorValue ?? Colors.grey,
                            radius: 30,
                            showTitle: false,
                          ),
                      ],
                    )),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final e in (subjectRange.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(6))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: store.subjectById(e.key)?.colorValue,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(store.subjectById(e.key)?.name ?? '?',
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                              Text('${(e.value / rangeTotal * 100).round()}%',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                            ]),
                          ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ],
          const SectionTitle('When you study'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
              child: SizedBox(
                height: 150,
                child: _Bars(
                  values: store.snapshot.hourBuckets.map((v) => v / 3600000).toList(),
                  labels: [for (var h = 0; h < 24; h++) h % 6 == 0 ? '${h}h' : ''],
                  color: Colors.deepOrange,
                  barWidth: 7,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;
  final double? barWidth;
  const _Bars({required this.values, required this.labels, required this.color, this.barWidth});

  @override
  Widget build(BuildContext context) {
    final maxY = values.fold<double>(0, (a, b) => b > a ? b : a);
    final width = barWidth ?? (values.length > 12 ? 6.0 : 18.0);
    final avg = values.isEmpty ? 0.0 : values.reduce((a, b) => a + b) / values.length;
    return BarChart(BarChartData(
      maxY: maxY <= 0 ? 1 : maxY * 1.2,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: Theme.of(context).dividerColor.withValues(alpha: 0.3), strokeWidth: 1),
      ),
      extraLinesData: ExtraLinesData(horizontalLines: [
        if (avg > 0)
          HorizontalLine(
            y: avg,
            color: color.withValues(alpha: 0.6),
            strokeWidth: 1.5,
            dashArray: [6, 4],
          ),
      ]),
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
            reservedSize: 32,
            getTitlesWidget: (v, m) {
              if (v == m.max) return const SizedBox.shrink();
              return Text('${v.toStringAsFixed(v < 2 && v > 0 ? 1 : 0)}h', style: const TextStyle(fontSize: 9));
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, m) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(labels[v.toInt()], style: const TextStyle(fontSize: 10)),
            ),
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < values.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: values[i],
              width: width,
              borderRadius: BorderRadius.circular(width / 3),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [color.withValues(alpha: 0.6), color],
              ),
            ),
          ]),
      ],
    ));
  }
}

void showDayBreakdown(BuildContext context, String key) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final store = ctx.watch<StudyStore>();
      final items = store.breakdownForDay(key);
      final total = items.fold<int>(0, (a, e) => a + e.ms);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
            Text(prettyDayKey(key, store.todayKey), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text('${formatDuration(total)} studied',
                style: TextStyle(color: Theme.of(ctx).colorScheme.primary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('No study time on this day.', textAlign: TextAlign.center)),
            for (final e in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SubjectAvatar(e.subject, size: 38),
                title: Text(e.chapter?.name ?? 'General study'),
                subtitle: Text(e.subject.name),
                trailing: Text(formatDuration(e.ms), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
          ]),
        ),
      );
    },
  );
}
