import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../logic/day_utils.dart';
import '../theme.dart';

Color heatColor(BuildContext context, int ms) {
  final scheme = Theme.of(context).colorScheme;
  final h = ms / 3600000;
  if (h >= 10) return gold;
  if (h >= 6) return scheme.primary;
  if (h >= 3) return scheme.primary.withValues(alpha: 0.7);
  if (h >= 1) return scheme.primary.withValues(alpha: 0.45);
  if (ms > 0) return scheme.primary.withValues(alpha: 0.22);
  return scheme.onSurface.withValues(alpha: 0.06);
}

/// GitHub style contribution grid for the last [weeks] weeks.
class YearHeatmap extends StatelessWidget {
  final Map<String, int> daily;
  final String todayKey;
  final int weeks;
  final void Function(String key)? onTap;

  const YearHeatmap({super.key, required this.daily, required this.todayKey, this.weeks = 26, this.onTap});

  @override
  Widget build(BuildContext context) {
    const cell = 14.0;
    const gap = 3.0;
    final today = dateOfKey(todayKey);
    // Last column ends with today's week (Mon..Sun rows).
    final lastMonday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    final firstMonday = DateTime(lastMonday.year, lastMonday.month, lastMonday.day - 7 * (weeks - 1));
    final monthFmt = DateFormat('MMM');

    final columns = <Widget>[];
    for (var w = 0; w < weeks; w++) {
      final weekStart = DateTime(firstMonday.year, firstMonday.month, firstMonday.day + 7 * w);
      final showMonth = weekStart.day <= 7;
      final cells = <Widget>[
        SizedBox(
          height: 14,
          child: showMonth
              ? Text(monthFmt.format(weekStart),
                  style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant))
              : null,
        ),
      ];
      for (var d = 0; d < 7; d++) {
        final date = DateTime(weekStart.year, weekStart.month, weekStart.day + d);
        final key = keyOfDate(date);
        final future = key.compareTo(todayKey) > 0;
        final ms = daily[key] ?? 0;
        cells.add(Padding(
          padding: const EdgeInsets.only(bottom: gap),
          child: GestureDetector(
            onTap: future || onTap == null ? null : () => onTap!(key),
            child: Tooltip(
              message: '${DateFormat('d MMM').format(date)} · ${formatDuration(ms)}',
              child: Container(
                width: cell,
                height: cell,
                decoration: BoxDecoration(
                  color: future ? Colors.transparent : heatColor(context, ms),
                  borderRadius: BorderRadius.circular(3.5),
                  border: key == todayKey
                      ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 1.2)
                      : null,
                ),
              ),
            ),
          ),
        ));
      }
      columns.add(Padding(
        padding: const EdgeInsets.only(right: gap),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: cells),
      ));
    }

    const dayLabels = ['M', '', 'W', '', 'F', '', 'S'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(children: [
          const SizedBox(height: 14),
          for (final l in dayLabels)
            SizedBox(
              height: cell + gap,
              width: 14,
              child: Text(l,
                  style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
        ]),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(children: columns),
          ),
        ),
      ],
    );
  }
}

class HeatLegend extends StatelessWidget {
  const HeatLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final samples = [0, 1, 3600000, 3 * 3600000, 6 * 3600000, 10 * 3600000];
    final style = TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('Less ', style: style),
        for (final s in samples)
          Container(
            width: 11,
            height: 11,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(color: heatColor(context, s), borderRadius: BorderRadius.circular(3)),
          ),
        Text(' 10h+', style: style),
      ],
    );
  }
}

/// Month calendar with intensity-coloured days (v1 "Growth Calendar").
class MonthCalendar extends StatefulWidget {
  final Map<String, int> daily;
  final String todayKey;
  final void Function(String key) onTap;
  const MonthCalendar({super.key, required this.daily, required this.todayKey, required this.onTap});

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final t = dateOfKey(widget.todayKey);
    _month = DateTime(t.year, t.month);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = DateTime(_month.year, _month.month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = first.weekday - 1;
    var monthTotal = 0;
    for (var d = 1; d <= daysInMonth; d++) {
      monthTotal += widget.daily[keyOfDate(DateTime(_month.year, _month.month, d))] ?? 0;
    }
    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final key = keyOfDate(DateTime(_month.year, _month.month, d));
      final ms = widget.daily[key] ?? 0;
      final future = key.compareTo(widget.todayKey) > 0;
      final bg = ms > 0 ? heatColor(context, ms) : Colors.transparent;
      final strong = ms >= 3 * 3600000;
      final fg = ms >= 10 * 3600000 ? Colors.black : (strong ? Colors.white : scheme.onSurface);
      cells.add(InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: future ? null : () => widget.onTap(key),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: key == widget.todayKey ? Border.all(color: scheme.primary, width: 2) : null,
          ),
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$d',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: future ? scheme.onSurface.withValues(alpha: 0.3) : fg)),
            if (ms > 0)
              Text('${formatHours(ms)}h', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: fg)),
          ]),
        ),
      ));
    }

    return Column(children: [
      Row(children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
        ),
        Expanded(
          child: Column(children: [
            Text(DateFormat('MMMM yyyy').format(_month),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text('${formatDuration(monthTotal)} this month',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
        ),
      ]),
      const SizedBox(height: 6),
      Row(
        children: [
          for (final l in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
            Expanded(
              child: Center(
                  child: Text(l,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant))),
            ),
        ],
      ),
      const SizedBox(height: 6),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        children: cells,
      ),
    ]);
  }
}
