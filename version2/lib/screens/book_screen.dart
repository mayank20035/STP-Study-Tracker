import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../logic/day_utils.dart';
import '../logic/stats.dart';
import '../models/models.dart';
import '../state/study_store.dart';
import '../widgets/common.dart';
import '../widgets/gate.dart';
import '../widgets/subject_form.dart';

// ---------------------------------------------------------------- palette

class BookPalette {
  final Color desk1, desk2, paper, paperEdge, rule, margin, ink, inkSoft, ribbon, cover1, cover2, gilt;
  const BookPalette({
    required this.desk1,
    required this.desk2,
    required this.paper,
    required this.paperEdge,
    required this.rule,
    required this.margin,
    required this.ink,
    required this.inkSoft,
    required this.ribbon,
    required this.cover1,
    required this.cover2,
    required this.gilt,
  });

  static const light = BookPalette(
    desk1: Color(0xFF8D6E63),
    desk2: Color(0xFF5D4037),
    paper: Color(0xFFFBF6E9),
    paperEdge: Color(0xFFE9DFC6),
    rule: Color(0xFFCFDDEE),
    margin: Color(0xFFE6A1A1),
    ink: Color(0xFF26285A),
    inkSoft: Color(0xFF6E6C8E),
    ribbon: Color(0xFFC62828),
    cover1: Color(0xFF6D1B1B),
    cover2: Color(0xFF3B0E0E),
    gilt: Color(0xFFE5BE5A),
  );

  static const dark = BookPalette(
    desk1: Color(0xFF2A211B),
    desk2: Color(0xFF14100D),
    paper: Color(0xFF29251F),
    paperEdge: Color(0xFF1E1B17),
    rule: Color(0xFF3A3A44),
    margin: Color(0xFF7A3B3B),
    ink: Color(0xFFEDE3CF),
    inkSoft: Color(0xFFA89F8C),
    ribbon: Color(0xFFE53935),
    cover1: Color(0xFF5A1717),
    cover2: Color(0xFF2B0A0A),
    gilt: Color(0xFFD9B04A),
  );

  static BookPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

const _serif = 'serif';

TextStyle _ink(BookPalette p,
        {double size = 16, FontWeight weight = FontWeight.w500, bool italic = false, Color? color}) =>
    TextStyle(
      fontFamily: _serif,
      fontSize: size,
      fontWeight: weight,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      color: color ?? p.ink,
      height: 1.25,
    );

// ---------------------------------------------------------------- screen

class BookScreen extends StatefulWidget {
  const BookScreen({super.key});

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> with TickerProviderStateMixin {
  static bool _coverShownThisLaunch = false;

  late String _key;
  String? _neighbor;
  double _progress = 0; // >0 turning forward, <0 turning back
  late final AnimationController _turn;
  double _from = 0, _to = 0;
  late final AnimationController _cover;
  bool _showCover = !_coverShownThisLaunch;

  @override
  void initState() {
    super.initState();
    _key = context.read<StudyStore>().todayKey;
    _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))
      ..addListener(() {
        setState(() => _progress = _from + (_to - _from) * Curves.easeInOutCubic.transform(_turn.value));
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _settle();
      });
    _cover = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) setState(() => _showCover = false);
      });
    if (_showCover) {
      _coverShownThisLaunch = true;
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted) _cover.forward();
      });
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    _cover.dispose();
    super.dispose();
  }

  void _settle() {
    setState(() {
      if (_to != 0 && _neighbor != null) _key = _neighbor!;
      _progress = 0;
      _neighbor = null;
    });
  }

  void _animateTo(double target) {
    _from = _progress;
    _to = target;
    _turn.forward(from: 0);
  }

  /// Turn to any page with a page-flip animation.
  void goTo(String key) {
    if (key == _key || _turn.isAnimating) return;
    _neighbor = key;
    HapticFeedback.selectionClick();
    _progress = key.compareTo(_key) > 0 ? 0.001 : -0.001;
    _animateTo(_progress.sign);
  }

  void _onDragUpdate(DragUpdateDetails d, double width) {
    if (_turn.isAnimating) return;
    final next = (_progress - d.delta.dx / width * 1.2).clamp(-1.0, 1.0);
    if (next != 0 && (_neighbor == null || next.sign != _progress.sign)) {
      _neighbor = addDays(_key, next > 0 ? 1 : -1);
    }
    setState(() => _progress = next);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_turn.isAnimating || _progress == 0) return;
    final v = -(d.primaryVelocity ?? 0);
    final commit = _progress.abs() > 0.3 || (v.abs() > 500 && v.sign == _progress.sign);
    if (commit) HapticFeedback.selectionClick();
    _animateTo(commit ? _progress.sign : 0);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: dateOfKey(_key),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Open the book at…',
    );
    if (d != null) goTo(keyOfDate(d));
  }

  @override
  Widget build(BuildContext context) {
    final p = BookPalette.of(context);
    final store = context.watch<StudyStore>();
    final today = store.todayKey;

    Widget page(String key) => RepaintBoundary(child: BookPage(dayKey: key, onTurnTo: goTo));

    Widget flipping(Widget child, double angle, double shade) => Transform(
          alignment: Alignment.centerLeft,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0011)
            ..rotateY(angle),
          child: Stack(children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.black.withValues(alpha: shade * 0.15),
                      Colors.black.withValues(alpha: shade * 0.55),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        );

    Widget pages;
    final n = _neighbor;
    if (_progress == 0 || n == null) {
      pages = page(_key);
    } else if (_progress > 0) {
      pages = Stack(children: [page(n), flipping(page(_key), -_progress * math.pi / 2, _progress)]);
    } else {
      final b = -_progress;
      pages = Stack(children: [page(_key), flipping(page(n), -(1 - b) * math.pi / 2, 1 - b)]);
    }

    return Scaffold(
      backgroundColor: p.desk2,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.4, -0.8),
            radius: 1.4,
            colors: [p.desk1, p.desk2],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(children: [
                const Text('📖', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('My To-Do Book',
                      style: _ink(p, size: 22, weight: FontWeight.w800, color: const Color(0xFFFFF3D6))),
                ),
                IconButton(
                  tooltip: 'Previous page',
                  icon: const Icon(Icons.chevron_left, color: Color(0xFFFFF3D6)),
                  onPressed: () => goTo(addDays(_key, -1)),
                ),
                IconButton(
                  tooltip: 'Jump to a date',
                  icon: const Icon(Icons.calendar_month, color: Color(0xFFFFF3D6)),
                  onPressed: _pickDate,
                ),
                IconButton(
                  tooltip: 'Next page',
                  icon: const Icon(Icons.chevron_right, color: Color(0xFFFFF3D6)),
                  onPressed: () => goTo(addDays(_key, 1)),
                ),
              ]),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                return Stack(children: [
                  // Page stack edges for thickness.
                  Positioned(
                    left: 14,
                    right: 6,
                    top: 10,
                    bottom: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: p.paperEdge,
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 10,
                    top: 6,
                    bottom: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color.lerp(p.paperEdge, p.paper, 0.5),
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    left: 10,
                    right: 14,
                    top: 2,
                    bottom: 10,
                    child: GestureDetector(
                      onHorizontalDragUpdate: (d) => _onDragUpdate(d, c.maxWidth),
                      onHorizontalDragEnd: _onDragEnd,
                      child: pages,
                    ),
                  ),
                  if (_key != today)
                    Positioned(
                      right: 22,
                      bottom: 18,
                      child: FloatingActionButton.extended(
                        heroTag: 'book_today',
                        backgroundColor: p.ribbon,
                        foregroundColor: Colors.white,
                        onPressed: () => goTo(today),
                        icon: const Icon(Icons.bookmark),
                        label: const Text('Today'),
                      ),
                    ),
                  if (_showCover)
                    Positioned.fill(
                      left: 10,
                      right: 14,
                      top: 2,
                      bottom: 10,
                      child: GestureDetector(
                        onTap: () => _cover.forward(),
                        child: AnimatedBuilder(
                          animation: _cover,
                          builder: (_, child) {
                            final v = Curves.easeInCubic.transform(_cover.value);
                            return Opacity(
                              opacity: (1 - _cover.value * 0.6).clamp(0, 1),
                              child: Transform(
                                alignment: Alignment.centerLeft,
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, 0.0012)
                                  ..rotateY(-v * math.pi / 2),
                                child: child,
                              ),
                            );
                          },
                          child: _BookCover(name: store.profile.name),
                        ),
                      ),
                    ),
                ]);
              }),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- cover

class _BookCover extends StatelessWidget {
  final String name;
  const _BookCover({required this.name});

  @override
  Widget build(BuildContext context) {
    final p = BookPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(16), left: Radius.circular(4)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.cover1, p.cover2],
        ),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(4, 8))],
      ),
      child: Stack(children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 22,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.black.withValues(alpha: 0.45), Colors.transparent]),
            ),
          ),
        ),
        Positioned.fill(
          left: 36,
          right: 22,
          top: 22,
          bottom: 22,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: p.gilt.withValues(alpha: 0.8), width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('✦', style: TextStyle(color: p.gilt, fontSize: 28)),
              const SizedBox(height: 12),
              Text('STUDY', style: _ink(p, size: 40, weight: FontWeight.w900, color: p.gilt)),
              Text('JOURNAL', style: _ink(p, size: 28, weight: FontWeight.w700, color: p.gilt)),
              const SizedBox(height: 16),
              Container(width: 80, height: 2, color: p.gilt),
              const SizedBox(height: 16),
              Text(name, style: _ink(p, size: 20, italic: true, color: p.gilt)),
              Text(DateFormat('yyyy').format(DateTime.now()),
                  style: _ink(p, size: 14, color: p.gilt.withValues(alpha: 0.8))),
              const SizedBox(height: 30),
              Text('tap to open', style: _ink(p, size: 12, italic: true, color: p.gilt.withValues(alpha: 0.7))),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- page

class BookPage extends StatelessWidget {
  final String dayKey;
  final ValueChanged<String> onTurnTo;
  const BookPage({super.key, required this.dayKey, required this.onTurnTo});

  @override
  Widget build(BuildContext context) {
    final p = BookPalette.of(context);
    final store = context.watch<StudyStore>();
    final today = store.todayKey;
    final isToday = dayKey == today;
    final isPast = store.isPastDay(dayKey);
    final date = dateOfKey(dayKey);
    final plan = store.planFor(dayKey);
    final status = store.pageStatus(dayKey);
    final score = store.pageScore(dayKey);
    final pageNo = date.difference(DateTime(date.year)).inDays + 1;
    final quote = motivationalQuotes[dayKey.hashCode.abs() % motivationalQuotes.length];
    final carry = (isToday || !isPast) ? store.carryOverCandidates(addDays(dayKey, -1), dayKey) : const <PlanTask>[];
    final editable = !isPast;

    return Container(
      decoration: BoxDecoration(
        color: p.paper,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(14), left: Radius.circular(4)),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(2, 6))],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(14), left: Radius.circular(4)),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _PaperPainter(p))),
          ListView(
            padding: const EdgeInsets.fromLTRB(54, 18, 18, 90),
            children: [
              _PageHeader(
                dayKey: dayKey,
                isToday: isToday,
                pageNo: pageNo,
                onDateTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) onTurnTo(keyOfDate(d));
                },
              ),
              const SizedBox(height: 6),
              if (score.total > 0)
                Text(
                  '${score.done}/${score.total} done  ·  ${(score.percent * 100).round()}% of planned time',
                  style: _ink(p, size: 13, italic: true, color: p.inkSoft),
                ),
              if (carry.isNotEmpty) ...[
                const SizedBox(height: 10),
                _CarryOverBanner(fromKey: addDays(dayKey, -1), toKey: dayKey, count: carry.length),
              ],
              const SizedBox(height: 12),
              if (plan.tasks.isEmpty)
                _EmptyPageHint(isPast: isPast, isToday: isToday)
              else
                for (final t in plan.tasks) _TaskLine(dayKey: dayKey, task: t),
              if (editable) ...[
                const SizedBox(height: 4),
                _AddLine(dayKey: dayKey),
              ],
              if (isToday && plan.tasks.isNotEmpty && store.selectedTask == null) ...[
                const SizedBox(height: 10),
                Text('👆 Tap a subject to pick it — then its timer unlocks.',
                    style: _ink(p, size: 13, italic: true, color: p.ribbon)),
              ],
              const SizedBox(height: 22),
              _StickyNote(dayKey: dayKey, editable: true),
              const SizedBox(height: 22),
              Center(
                child: Text('“$quote”',
                    textAlign: TextAlign.center, style: _ink(p, size: 13, italic: true, color: p.inkSoft)),
              ),
              const SizedBox(height: 10),
              Center(child: Text('— $pageNo —', style: _ink(p, size: 12, color: p.inkSoft))),
            ],
          ),
          if (isToday)
            Positioned(
              right: 26,
              top: -4,
              child: CustomPaint(size: const Size(22, 64), painter: _RibbonPainter(p.ribbon)),
            ),
          if (status == PageStatus.conquered || status == PageStatus.partial || status == PageStatus.missed)
            Positioned(right: 16, top: 70, child: IgnorePointer(child: _Stamp(status: status))),
          if (status == PageStatus.conquered)
            const Positioned(
              right: 30,
              top: 16,
              child: IgnorePointer(child: Text('⭐', style: TextStyle(fontSize: 30))),
            ),
        ]),
      ),
    );
  }
}

class _PaperPainter extends CustomPainter {
  final BookPalette p;
  _PaperPainter(this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final rule = Paint()
      ..color = p.rule
      ..strokeWidth = 1;
    for (double y = 96; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
    }
    final margin = Paint()
      ..color = p.margin
      ..strokeWidth = 1.4;
    canvas.drawLine(const Offset(44, 0), Offset(44, size.height), margin);
    canvas.drawLine(const Offset(47, 0), Offset(47, size.height), margin..strokeWidth = 0.6);

    // Spine shadow.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 26, size.height),
      Paint()
        ..shader = LinearGradient(colors: [Colors.black.withValues(alpha: 0.22), Colors.transparent])
            .createShader(Rect.fromLTWH(0, 0, 26, size.height)),
    );

    // Spiral binding.
    final hole = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final ring = Paint()
      ..color = const Color(0xFF9E9E9E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;
    for (double y = 24; y < size.height - 10; y += 34) {
      canvas.drawCircle(Offset(18, y), 4.5, hole);
      canvas.drawArc(Rect.fromCircle(center: Offset(10, y), radius: 9), -math.pi / 2, math.pi, false, ring);
    }
  }

  @override
  bool shouldRepaint(_PaperPainter old) => old.p != p;
}

class _RibbonPainter extends CustomPainter {
  final Color color;
  _RibbonPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height - 9)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height - 10),
        Paint()
          ..color = Colors.white24
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.color != color;
}

class _PageHeader extends StatelessWidget {
  final String dayKey;
  final bool isToday;
  final int pageNo;
  final VoidCallback onDateTap;
  const _PageHeader({required this.dayKey, required this.isToday, required this.pageNo, required this.onDateTap});

  @override
  Widget build(BuildContext context) {
    final p = BookPalette.of(context);
    final store = context.read<StudyStore>();
    final date = dateOfKey(dayKey);
    final label = isToday
        ? 'TODAY'
        : dayKey == addDays(store.todayKey, 1)
            ? 'TOMORROW'
            : dayKey == addDays(store.todayKey, -1)
                ? 'YESTERDAY'
                : (store.isPastDay(dayKey) ? 'MEMORIES' : 'PLANNING AHEAD');
    return InkWell(
      onTap: onDateTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: _ink(p, size: 11, weight: FontWeight.w800, color: isToday ? p.ribbon : p.inkSoft)
                  .copyWith(letterSpacing: 2.5)),
          Text(DateFormat('EEEE').format(date), style: _ink(p, size: 32, weight: FontWeight.w800, italic: true)),
          Text(DateFormat('d MMMM yyyy').format(date), style: _ink(p, size: 16, color: p.inkSoft)),
        ]),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  final PageStatus status;
  const _Stamp({required this.status});

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (status) {
      PageStatus.conquered => ('DAY\nCONQUERED', const Color(0xFF2E7D32)),
      PageStatus.partial => ('PARTLY\nDONE', const Color(0xFFEF6C00)),
      _ => ('MISSED', const Color(0xFFC62828)),
    };
    return Transform.rotate(
      angle: -0.28,
      child: Opacity(
        opacity: 0.72,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: _serif,
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 2,
                  height: 1.1)),
        ),
      ),
    );
  }
}

class _EmptyPageHint extends StatelessWidget {
  final bool isPast;
  final bool isToday;
  const _EmptyPageHint({required this.isPast, required this.isToday});

  @override
  Widget build(BuildContext context) {
    final p = BookPalette.of(context);
    final text = isPast
        ? 'Nothing was planned on this page.'
        : isToday
            ? 'A fresh page! ✍️\nAdd the subjects you want to study today and how long for each.'
            : 'Plan ahead — what will you study on this day?';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(text, style: _ink(p, size: 17, italic: true, color: p.inkSoft)),
    );
  }
}

class _CarryOverBanner extends StatelessWidget {
  final String fromKey;
  final String toKey;
  final int count;
  const _CarryOverBanner({required this.fromKey, required this.toKey, required this.count});

  @override
  Widget build(BuildContext context) {
    final p = BookPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE082).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.6)),
      ),
      child: Row(children: [
        const Text('📌', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$count unfinished from the page before',
              style: _ink(p, size: 14, weight: FontWeight.w600)),
        ),
        TextButton(
          onPressed: () {
            final n = context.read<StudyStore>().carryOverUnfinished(fromKey, toKey);
            showSnack(context, '📌 Carried over $n task${n == 1 ? '' : 's'} with their remaining time');
          },
          child: const Text('Carry over'),
        ),
      ]),
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
    final p = BookPalette.of(context);
    final store = context.watch<StudyStore>();
    final sub = store.subjectById(task.subjectId);
    if (sub == null) return const SizedBox.shrink();
    final isToday = dayKey == store.todayKey;
    final isPast = store.isPastDay(dayKey);
    final progress = store.taskProgressMs(dayKey, task);
    final done = progress >= task.targetMs;
    final selected = isToday && store.selectedTask?.id == task.id;
    final running = selected && store.isRunning(sub.id);
    final frac = (progress / task.targetMs).clamp(0.0, 1.0);

    Future<void> onTap() async {
      if (isPast) return;
      if (isToday && !selected && !done) {
        final g = store.selectTask(task.id);
        if (g == StartGate.ok) {
          showSnack(context, '📌 ${sub.name} picked — its timer is unlocked!');
        }
        return;
      }
      await _taskActions(context, dayKey, task);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: selected ? sub.colorValue.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: isPast ? null : () => _taskActions(context, dayKey, task),
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sub.colorValue.withValues(alpha: 0.7), width: 1.6),
                  )
                : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _InkCheck(done: done, color: sub.colorValue),
                const SizedBox(width: 8),
                Text(sub.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    sub.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _ink(p, size: 19, weight: FontWeight.w700).copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: sub.colorValue,
                      decorationThickness: 2.4,
                    ),
                  ),
                ),
                Text(formatDuration(task.targetMs), style: _ink(p, size: 17, weight: FontWeight.w800, italic: true)),
              ]),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: _Highlighter(value: frac, color: sub.colorValue, running: running),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      done
                          ? '✔ ${formatDuration(progress)} studied — target smashed!'
                          : running
                              ? '⏱ ${formatClock(store.taskRemainingMs(dayKey, task))} left'
                              : '${formatDuration(progress)} of ${formatDuration(task.targetMs)}'
                                  '${selected ? '  ·  picked' : ''}',
                      style: _ink(p, size: 13, italic: true, color: done ? const Color(0xFF2E7D32) : p.inkSoft),
                    ),
                  ),
                  if (selected && !done)
                    _MiniButton(
                      icon: running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: running ? Theme.of(context).colorScheme.error : sub.colorValue,
                      onTap: () => showGateSnack(context, store, store.toggleTimer(sub.id)),
                    ),
                  if (done && !isPast)
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
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
        child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, color: Colors.white, size: 20)),
      ),
    );
  }
}

class _InkCheck extends StatelessWidget {
  final bool done;
  final Color color;
  const _InkCheck({required this.done, required this.color});

  @override
  Widget build(BuildContext context) {
    final p = BookPalette.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: done ? color : p.inkSoft, width: 2),
        color: done ? color : Colors.transparent,
      ),
      child: done ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
    );
  }
}

/// A highlighter-marker style progress stroke.
class _Highlighter extends StatefulWidget {
  final double value;
  final Color color;
  final bool running;
  const _Highlighter({required this.value, required this.color, required this.running});

  @override
  State<_Highlighter> createState() => _HighlighterState();
}

class _HighlighterState extends State<_Highlighter> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void initState() {
    super.initState();
    if (widget.running) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Highlighter old) {
    super.didUpdateWidget(old);
    if (widget.running && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!widget.running && _pulse.isAnimating) _pulse.stop();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, _) => CustomPaint(
        size: const Size(double.infinity, 12),
        painter: _HighlighterPainter(
          value: widget.value,
          color: widget.color,
          glow: widget.running ? _pulse.value : 0,
          track: BookPalette.of(context).rule,
        ),
      ),
    );
  }
}

class _HighlighterPainter extends CustomPainter {
  final double value;
  final Color color;
  final double glow;
  final Color track;
  _HighlighterPainter({required this.value, required this.color, required this.glow, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    // Dashed pencil guide.
    final dash = Paint()
      ..color = track
      ..strokeWidth = 1.5;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, h * 0.6), Offset(math.min(x + 4, size.width), h * 0.6), dash);
    }
    if (value <= 0) return;
    final w = size.width * value;
    final path = Path()
      ..moveTo(3, 1)
      ..lineTo(w, 0)
      ..lineTo(w - 3, h)
      ..lineTo(0, h - 1)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.35 + glow * 0.3));
    if (glow > 0) {
      canvas.drawCircle(Offset(w - 1, h / 2), 4 + glow * 2, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_HighlighterPainter old) =>
      old.value != value || old.glow != glow || old.color != color || old.track != track;
}

Future<void> _taskActions(BuildContext context, String dayKey, PlanTask task) async {
  final store = context.read<StudyStore>();
  final sub = store.subjectById(task.subjectId);
  if (sub == null) return;
  final isToday = dayKey == store.todayKey;
  final selected = isToday && store.selectedTask?.id == task.id;
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
        if (isToday && !selected && !done)
          ListTile(
            leading: const Icon(Icons.push_pin_outlined),
            title: const Text('Pick this task'),
            onTap: () => Navigator.pop(ctx, 'select'),
          ),
        if (selected)
          ListTile(
            leading: const Icon(Icons.push_pin),
            title: const Text('Unpick (stops its timer)'),
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
      store.selectTask(task.id);
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

// ---------------------------------------------------------------- add line

class _AddLine extends StatelessWidget {
  final String dayKey;
  const _AddLine({required this.dayKey});

  @override
  Widget build(BuildContext context) {
    final p = BookPalette.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showAddTaskSheet(context, dayKey),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(children: [
          Icon(Icons.add_circle_outline, color: p.ribbon),
          const SizedBox(width: 10),
          Text('Add subject…', style: _ink(p, size: 18, italic: true, color: p.ribbon)),
        ]),
      ),
    );
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
          Text('1. Choose one of your subjects', style: TextStyle(color: scheme.onSurfaceVariant)),
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
          Text('2. How long will you study it?', style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          DurationStepper(minutes: _minutes, onChanged: (m) => setState(() => _minutes = m)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              icon: const Icon(Icons.edit_note),
              label: const Text('Write it in the book'),
              onPressed: _subjectId == null
                  ? null
                  : () {
                      final r = store.addPlanTask(widget.dayKey, _subjectId!, _minutes * 60000);
                      if (r == PlanResult.ok) {
                        Navigator.pop(context);
                      } else {
                        showSnack(context, switch (r) {
                          PlanResult.duplicateSubject => 'That subject is already on this page',
                          PlanResult.invalidTarget => 'Pick between 1 minute and 24 hours',
                          PlanResult.pastDay => 'You can\'t change the past 🙂',
                          _ => 'Could not add that subject',
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

// ---------------------------------------------------------------- sticky note

class _StickyNote extends StatelessWidget {
  final String dayKey;
  final bool editable;
  const _StickyNote({required this.dayKey, required this.editable});

  static const moods = ['😫', '😕', '😐', '🙂', '🤩'];

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final plan = store.planFor(dayKey);
    const ink = Color(0xFF4E3B00);
    return Transform.rotate(
      angle: -0.015,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF59D),
          borderRadius: const BorderRadius.only(bottomRight: Radius.circular(18)),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(2, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('📝', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('How did it go?',
                  style: TextStyle(fontFamily: _serif, fontWeight: FontWeight.w800, color: ink, fontSize: 15)),
            ),
            for (var i = 0; i < moods.length; i++)
              GestureDetector(
                onTap: editable ? () => store.setDayMood(dayKey, plan.mood == i ? null : i) : null,
                child: AnimatedScale(
                  scale: plan.mood == i ? 1.35 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: Opacity(
                    opacity: plan.mood == null || plan.mood == i ? 1 : 0.35,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(moods[i], style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          InkWell(
            onTap: !editable
                ? null
                : () async {
                    final t = await promptText(context,
                        title: 'Note for ${prettyDayKey(dayKey, store.todayKey)}',
                        initial: plan.note,
                        hint: 'Wins, struggles, what to fix tomorrow…');
                    if (t != null) store.setDayNote(dayKey, t);
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                plan.note.isEmpty ? 'Tap to write a note…' : plan.note,
                style: TextStyle(
                  fontFamily: _serif,
                  fontStyle: FontStyle.italic,
                  fontSize: 15,
                  color: plan.note.isEmpty ? ink.withValues(alpha: 0.5) : ink,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
