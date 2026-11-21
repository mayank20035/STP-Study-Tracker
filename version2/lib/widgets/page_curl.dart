import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Geometry of a soft page curl, like a paper page being turned from its
/// right-hand corner: the corner is lifted and folded back along a fold line,
/// showing the back of the page (the "flap") and the page underneath.
class CurlGeometry {
  /// The page area.
  final Rect page;

  /// Where the turned corner started, and where it is now.
  final Offset corner;
  final Offset touch;

  /// The part of the turning page that still lies flat.
  late final List<Offset> front;

  /// The part that has been lifted (the page below shows through here).
  late final List<Offset> lifted;

  /// The back of the lifted part, folded over the front.
  late final List<Offset> flap;

  /// A point on the fold line and the fold's unit normal (pointing to the corner side).
  late final Offset mid;
  late final Offset normal;

  CurlGeometry(this.page, this.corner, this.touch) {
    final rect = [page.topLeft, page.topRight, page.bottomRight, page.bottomLeft];
    final d = corner - touch;
    final len = d.distance;
    if (len < 0.5) {
      front = rect;
      lifted = const [];
      flap = const [];
      mid = corner;
      normal = const Offset(1, 0);
      return;
    }
    normal = d / len;
    mid = (corner + touch) / 2;
    front = clipHalfPlane(rect, mid, -normal);
    lifted = clipHalfPlane(rect, mid, normal);
    var f = lifted.map(reflect).toList();
    // The flap never leaves the page.
    f = clipHalfPlane(f, page.topLeft, const Offset(1, 0));
    f = clipHalfPlane(f, page.topRight, const Offset(-1, 0));
    f = clipHalfPlane(f, page.topLeft, const Offset(0, 1));
    f = clipHalfPlane(f, page.bottomLeft, const Offset(0, -1));
    flap = f;
  }

  /// The curl at turn progress [t] (0 = flat, 1 = fully turned). The corner
  /// travels across the page along a gentle arc, like a hand turning it.
  factory CurlGeometry.at(Rect page, double t, {bool fromTop = false}) {
    final corner = fromTop ? page.topRight : page.bottomRight;
    final lift = math.sin(math.pi * t) * page.height * 0.12;
    final touch = Offset(page.right - 2 * page.width * t, fromTop ? page.top + lift : page.bottom - lift);
    return CurlGeometry(page, corner, touch);
  }

  /// Distance from the fold line to the far edge of the flap.
  double get flapDepth => (corner - touch).distance / 2;

  Offset reflect(Offset p) {
    final s = (p - mid).dx * normal.dx + (p - mid).dy * normal.dy;
    return p - normal * (2 * s);
  }

  /// Keeps the part of convex polygon [poly] where (p - origin) · n >= 0.
  static List<Offset> clipHalfPlane(List<Offset> poly, Offset origin, Offset n) {
    if (poly.isEmpty) return const [];
    double side(Offset p) => (p.dx - origin.dx) * n.dx + (p.dy - origin.dy) * n.dy;
    final out = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      final sa = side(a), sb = side(b);
      if (sa >= 0) out.add(a);
      if ((sa >= 0) != (sb >= 0)) out.add(Offset.lerp(a, b, sa / (sa - sb))!);
    }
    return out;
  }

  static double area(List<Offset> poly) {
    var a = 0.0;
    for (var i = 0; i < poly.length; i++) {
      final p = poly[i], q = poly[(i + 1) % poly.length];
      a += p.dx * q.dy - q.dx * p.dy;
    }
    return a.abs() / 2;
  }

  static Path pathOf(List<Offset> poly) {
    final path = Path();
    if (poly.isEmpty) return path;
    path.moveTo(poly.first.dx, poly.first.dy);
    for (final p in poly.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }
}

/// Shows [front] being turned with a page curl at progress [t], revealing
/// [back] underneath.
class PageCurl extends StatelessWidget {
  final Widget front;
  final Widget back;
  final double t;
  final bool fromTop;

  /// Space around the visible page inside each child (e.g. a card's margin).
  final EdgeInsets inset;
  final Color paper;

  const PageCurl({
    super.key,
    required this.front,
    required this.back,
    required this.t,
    required this.paper,
    this.fromTop = false,
    this.inset = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (t <= 0.0001) return front;
    if (t >= 0.9999) return back;
    return LayoutBuilder(builder: (context, c) {
      final page = inset.deflateRect(Offset.zero & c.biggest);
      final g = CurlGeometry.at(page, t, fromTop: fromTop);
      return Stack(fit: StackFit.expand, children: [
        back,
        IgnorePointer(child: CustomPaint(painter: _UnderShadowPainter(g))),
        ClipPath(clipper: _PolygonClipper(g.front), child: front),
        IgnorePointer(child: CustomPaint(painter: _FlapPainter(g, paper))),
      ]);
    });
  }
}

class _PolygonClipper extends CustomClipper<Path> {
  final List<Offset> poly;
  _PolygonClipper(this.poly);

  @override
  Path getClip(Size size) => CurlGeometry.pathOf(poly);

  @override
  bool shouldReclip(_PolygonClipper old) => true;
}

/// Soft shadow on the page underneath, strongest along the fold.
class _UnderShadowPainter extends CustomPainter {
  final CurlGeometry g;
  _UnderShadowPainter(this.g);

  @override
  void paint(Canvas canvas, Size size) {
    if (g.lifted.isEmpty) return;
    final reach = math.max(12.0, math.min(70.0, g.flapDepth * 0.6));
    canvas.save();
    canvas.clipPath(CurlGeometry.pathOf(g.lifted));
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        // The gradient runs across the fold line, into the revealed page.
        ..shader = ui.Gradient.linear(g.mid, g.mid + g.normal * reach, [
          Colors.black.withValues(alpha: 0.30),
          Colors.black.withValues(alpha: 0.0),
        ]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UnderShadowPainter old) => true;
}

/// The back of the turned paper: a glossy grey sheet with a highlight near
/// the bend, casting a shadow on the page below it.
class _FlapPainter extends CustomPainter {
  final CurlGeometry g;
  final Color paper;
  _FlapPainter(this.g, this.paper);

  @override
  void paint(Canvas canvas, Size size) {
    if (g.flap.length < 3) return;
    final path = CurlGeometry.pathOf(g.flap);
    canvas.drawShadow(path, Colors.black, 6, false);
    final depth = math.max(1.0, g.flapDepth);
    final grey = Color.lerp(paper, const Color(0xFF8A8F98), 0.55)!;
    canvas.drawPath(
      path,
      Paint()
        // From the bend (fold line) out to the lifted corner.
        ..shader = ui.Gradient.linear(
          g.mid,
          g.mid - g.normal * depth,
          [
            Color.lerp(grey, Colors.black, 0.25)!,
            Color.lerp(paper, Colors.white, 0.85)!,
            Color.lerp(paper, grey, 0.35)!,
            Color.lerp(paper, grey, 0.15)!,
          ],
          const [0.0, 0.18, 0.55, 1.0],
        ),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = Colors.black.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_FlapPainter old) => true;
}
