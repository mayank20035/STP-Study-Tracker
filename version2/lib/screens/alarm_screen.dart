import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../logic/day_utils.dart';
import '../state/study_store.dart';

/// Full-screen "target reached" alarm. It stays until the user presses Stop
/// (or stops it from the notification).
class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> with TickerProviderStateMixin {
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  Timer? _buzz;

  @override
  void initState() {
    super.initState();
    _buzz = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      HapticFeedback.heavyImpact().catchError((_) {});
    });
  }

  @override
  void dispose() {
    _buzz?.cancel();
    _shake.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudyStore>();
    final alarm = store.alarm;
    final sub = store.subjectById(alarm?.subjectId);
    final task = alarm == null ? null : store.planFor(alarm.dayKey).taskById(alarm.taskId);
    final color = sub?.colorValue ?? Colors.deepPurple;
    final studied = alarm == null || task == null ? 0 : store.taskProgressMs(alarm.dayKey, task);
    final canExtend = alarm != null && alarm.dayKey == store.todayKey && task != null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(color, Colors.black, 0.35)!, const Color(0xFF0E0B16)],
            ),
          ),
          child: SafeArea(
            child: Column(children: [
              const Spacer(),
              AnimatedBuilder(
                animation: _shake,
                builder: (_, child) {
                  // Ring-ring: quick wiggle, then a pause.
                  final t = _shake.value;
                  final angle = t < 0.5 ? math.sin(t * math.pi * 12) * 0.35 * (1 - t * 2) : 0.0;
                  return Transform.rotate(angle: angle, child: child);
                },
                child: const Text('⏰', style: TextStyle(fontSize: 110)),
              ),
              const SizedBox(height: 18),
              const Text('TARGET REACHED!',
                  style: TextStyle(
                      color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 10),
              if (sub != null)
                Text('${sub.emoji}  ${sub.name}',
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                task == null
                    ? 'Great work!'
                    : 'You studied ${formatDuration(studied)} of your ${formatDuration(task.targetMs)} plan.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text('The page in your To-Do book is ticked ✔',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
              const Spacer(),
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) {
                  final v = _pulse.value;
                  return Stack(alignment: Alignment.center, children: [
                    for (final k in [0.0, 0.5])
                      Opacity(
                        opacity: (1 - ((v + k) % 1)).clamp(0, 1) * 0.5,
                        child: Container(
                          width: 150 + ((v + k) % 1) * 90,
                          height: 150 + ((v + k) % 1) * 90,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent),
                        ),
                      ),
                    child!,
                  ]);
                },
                child: Material(
                  color: Colors.red.shade600,
                  shape: const CircleBorder(),
                  elevation: 10,
                  child: InkWell(
                    key: const ValueKey('alarm_stop'),
                    customBorder: const CircleBorder(),
                    onTap: () {
                      // The app shell closes this page once the alarm is cleared.
                      store.stopAlarm();
                    },
                    child: const SizedBox(
                      width: 150,
                      height: 150,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.stop_rounded, color: Colors.white, size: 60),
                        Text('STOP',
                            style: TextStyle(
                                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3)),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 34),
              if (canExtend)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  ),
                  onPressed: () {
                    store.extendAfterAlarm(15);
                  },
                  icon: const Icon(Icons.more_time),
                  label: const Text('Stop & keep going +15 min'),
                ),
              const SizedBox(height: 40),
            ]),
          ),
        ),
      ),
    );
  }
}
