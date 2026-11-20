import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';

class ProgressRing extends StatelessWidget {
  final double progress;
  final double size;
  final double stroke;
  final Color color;
  final Color? trackColor;
  final Widget? child;

  const ProgressRing({
    super.key,
    required this.progress,
    required this.color,
    this.size = 120,
    this.stroke = 12,
    this.trackColor,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress.clamp(0, 1).toDouble()),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => CustomPaint(
          painter: _RingPainter(
            progress: v,
            color: color,
            track: trackColor ?? color.withValues(alpha: 0.15),
            stroke: stroke,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color track;
  final double stroke;
  _RingPainter({required this.progress, required this.color, required this.track, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    if (progress <= 0) return;
    final fg = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [color.withValues(alpha: 0.6), color],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * progress, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

class LinearBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;
  const LinearBar({super.key, required this.value, required this.color, this.height = 8});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1).toDouble(),
        minHeight: height,
        color: color,
        backgroundColor: color.withValues(alpha: 0.15),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  const StatTile({super.key, required this.label, required this.value, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 18, color: c),
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            Text(label,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class MedalPills extends StatelessWidget {
  final Medals medals;
  const MedalPills(this.medals, {super.key});

  @override
  Widget build(BuildContext context) {
    Widget pill(Color c, int n) => Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withValues(alpha: 0.6)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.military_tech, size: 13, color: c),
            const SizedBox(width: 2),
            Text('$n', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
          ]),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (medals.gold > 0) pill(gold, medals.gold),
      if (medals.silver > 0) pill(silver, medals.silver),
      if (medals.bronze > 0) pill(bronze, medals.bronze),
    ]);
  }
}

class SubjectAvatar extends StatelessWidget {
  final Subject subject;
  final double size;
  const SubjectAvatar(this.subject, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: subject.colorValue.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Text(subject.emoji, style: TextStyle(fontSize: size * 0.48)),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String body;
  final Widget? action;
  const EmptyState({super.key, required this.emoji, required this.title, required this.body, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Popup shown when Save is pressed with a field left empty (or invalid).
/// Shown as a dialog, so it is visible above bottom sheets too.
Future<void> showFillFieldsDialog(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.edit_note_rounded, size: 32),
      title: const Text('Fill in the details'),
      content: Text(message, textAlign: TextAlign.center),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}

/// "Please fill in Subject name and Target hours."
String missingFieldsMessage(List<String> fields) {
  final list = fields.length == 1
      ? fields.single
      : '${fields.sublist(0, fields.length - 1).join(', ')} and ${fields.last}';
  return 'Please fill in $list.';
}

/// Single-field text prompt. When [required] is true (the default), pressing
/// Save with an empty field shows a popup and keeps the prompt open.
/// [validate] can return an error message for a filled but invalid value.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String confirm = 'Save',
  TextInputType keyboard = TextInputType.text,
  bool required = true,
  String? Function(String value)? validate,
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() {
        final v = ctrl.text.trim();
        if (required && v.isEmpty) {
          showFillFieldsDialog(ctx, missingFieldsMessage([title]));
          return;
        }
        final error = v.isEmpty ? null : validate?.call(v);
        if (error != null) {
          showFillFieldsDialog(ctx, error);
          return;
        }
        Navigator.pop(ctx, v);
      }

      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: keyboard,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: submit, child: Text(confirm)),
        ],
      );
    },
  );
}

/// Validator for prompts that need a whole number above zero.
String? positiveWholeNumber(String v) {
  final n = int.tryParse(v);
  return n == null || n <= 0 ? 'Please enter a whole number above 0.' : null;
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Delete',
  bool destructive = true,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return res ?? false;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
