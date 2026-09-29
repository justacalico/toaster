import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/renderer.dart';
import '../core/vec3.dart';
import 'theme.dart';

/// Draws the 3D viewport: grid, objects, edit overlays, transform gizmo,
/// axis indicator and the HUD text.
class ViewportPainter extends CustomPainter {
  final AppState state;
  final int? gizmoHoverAxis;

  ViewportPainter(this.state, {this.gizmoHoverAxis});

  @override
  void paint(Canvas canvas, Size size) {
    final renderer = SceneRenderer(
      state.camera,
      shading: state.shading,
      showGrid: state.scene.showGrid && state.showOverlays,
      showAxes: state.scene.showAxes && state.showOverlays,
    )
      ..editTargetIndex = state.mode == EditorMode.edit ? state.editTarget : null
      ..selVerts = state.selVerts
      ..selEdges = state.selEdges
      ..selFaces = state.selFaces
      ..selectedObjects = state.selectedObjects;
    final frame = renderer.build(state.scene, size.width, size.height);

    canvas.drawRect(Offset.zero & size, Paint()..color = state.scene.backgroundColor);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final l in frame.grid) {
      linePaint
        ..color = l.color
        ..strokeWidth = l.width;
      canvas.drawLine(l.a, l.b, linePaint);
    }

    final polyPaint = Paint()..style = PaintingStyle.fill;
    for (final p in frame.polys) {
      final path = Path()..addPolygon(p.points, true);
      polyPaint.color = p.color;
      canvas.drawPath(path, polyPaint);
    }

    for (final l in frame.lines) {
      linePaint
        ..color = l.color
        ..strokeWidth = l.width;
      canvas.drawLine(l.a, l.b, linePaint);
    }

    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (final d in frame.dots) {
      dotPaint.color = d.color;
      canvas.drawCircle(d.at, d.radius, dotPaint);
      dotPaint.color = Colors.white.withValues(alpha: 0.25);
      canvas.drawCircle(d.at, d.radius, dotPaint..style = PaintingStyle.stroke);
      dotPaint.style = PaintingStyle.fill;
    }

    if (state.showOverlays) {
      _drawGizmo(canvas, size);
      _drawAxisIndicator(canvas, size);
      _drawHud(canvas, size);
    }
    if (state.transform != null) _drawTransformGuide(canvas, size);
  }

  // ---------- gizmo ----------

  static const axisColors = [
    Color(0xFFE05561),
    Color(0xFF6EBB5E),
    Color(0xFF5B8DEF),
  ];

  void _drawGizmo(Canvas canvas, Size size) {
    if (state.tool == Tool.select) return;
    final segs = gizmoSegments(state, size);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (final (axis, a, b) in segs) {
      final hot = gizmoHoverAxis == axis;
      paint
        ..color = hot ? T.selection : axisColors[axis]
        ..strokeWidth = hot ? 3.4 : 2.4;
      canvas.drawLine(a, b, paint);
      final fill = Paint()..color = hot ? T.selection : axisColors[axis];
      if (state.tool == Tool.move) {
        // arrowhead
        final dir = (b - a);
        final u = dir / dir.distance;
        final n = Offset(-u.dy, u.dx);
        canvas.drawPath(
          Path()
            ..addPolygon([b + u * 8, b + n * 4, b - n * 4], true),
          fill,
        );
      } else if (state.tool == Tool.scale) {
        canvas.drawRect(Rect.fromCenter(center: b, width: 8, height: 8), fill);
      }
    }
    if (state.tool == Tool.rotate) {
      // rotation rings: circle in the plane facing camera for each axis
      final pivot = segs.isEmpty ? null : segs.first.$2;
      if (pivot != null) {
        for (var a = 0; a < 3; a++) {
          final hot = gizmoHoverAxis == a;
          paint
            ..color = (hot ? T.selection : axisColors[a])
            ..strokeWidth = hot ? 2.8 : 1.8;
          canvas.drawCircle(pivot, 30 + a * 10, paint);
        }
      }
    }
    // center handle
    if (segs.isNotEmpty) {
      canvas.drawCircle(segs.first.$2, 4, Paint()..color = Colors.white);
    }
  }

  /// Axis indicator, top-right corner.
  void _drawAxisIndicator(Canvas canvas, Size size) {
    final center = Offset(size.width - 42, 42);
    final view = state.camera.view;
    final axes = [Vec3.unitX, Vec3.unitY, Vec3.unitZ];
    final labels = ['X', 'Y', 'Z'];
    for (var i = 0; i < 3; i++) {
      final d = view.transformDir(axes[i]);
      final end = center + Offset(d.x * 24, -d.y * 24);
      canvas.drawLine(
        center,
        end,
        Paint()
          ..color = axisColors[i]
          ..strokeWidth = 1.6,
      );
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: TextStyle(fontSize: 9, color: axisColors[i])),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, end - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _drawHud(Canvas canvas, Size size) {
    final modeName = state.mode == EditorMode.object
        ? 'Object Mode'
        : 'Edit Mode (${state.selMode.name})';
    final projName = state.camera.perspective ? 'Persp' : 'Ortho';
    final lines = [
      '$modeName  •  $projName  •  ${state.shading.name}',
      if (state.activeObj != null) 'Active: ${state.activeObj!.name}',
    ];
    final tp = TextPainter(textDirection: TextDirection.ltr);
    var y = 8.0;
    for (final l in lines) {
      tp.text = TextSpan(text: l, style: T.hint.copyWith(color: T.text.withValues(alpha: 0.8)));
      tp.layout();
      tp.paint(canvas, Offset(10, y));
      y += tp.height + 2;
    }
  }

  void _drawTransformGuide(Canvas canvas, Size size) {
    final t = state.transform!;
    final p = state.camera.project(t.pivot, size.width, size.height);
    if (p != null && t.startPointer != null) {
      final paint = Paint()
        ..color = T.selection
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(p.$1, p.$2), t.startPointer!, paint);
    }
    // label near cursor
    final tp = TextPainter(
      text: TextSpan(text: t.label, style: T.mono),
      textDirection: TextDirection.ltr,
    )..layout();
    final at = (t.startPointer ?? const Offset(60, 40)) + const Offset(14, -18);
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(ViewportPainter old) => true;
}

/// Pivot point of the current selection in world space.
Vec3 selectionPivot(AppState state) {
  if (state.mode == EditorMode.object) {
    if (state.selectedObjects.isEmpty) return Vec3.zero;
    var c = Vec3.zero;
    for (final i in state.selectedObjects) {
      c += state.scene.objects[i].location;
    }
    return c / state.selectedObjects.length.toDouble();
  }
  final obj = state.editObj;
  if (obj == null) return Vec3.zero;
  var c = Vec3.zero;
  var n = 0;
  final m = obj.mesh;
  final verts = <int>{};
  if (state.selMode == SelMode.vertex) {
    verts.addAll(state.selVerts);
  } else {
    for (final fi in state.selFaces) {
      if (fi < m.faces.length) verts.addAll(m.faces[fi]);
    }
    final all = m.allEdges().toList();
    for (final ei in state.selEdges) {
      if (ei < all.length) {
        verts.add(all[ei].$1);
        verts.add(all[ei].$2);
      }
    }
  }
  for (final v in verts) {
    c += obj.matrix.transformPoint(m.vertices[v]);
    n++;
  }
  return n == 0 ? obj.worldCenter : c / n.toDouble();
}

/// Projected axis segments for the active tool's gizmo:
/// (axis, centerScreen, tipScreen) for axes 0..2.
List<(int, Offset, Offset)> gizmoSegments(AppState state, Size size) {
  final t = state.transform;
  Vec3? pivot;
  if (t != null) {
    pivot = t.pivot;
  } else {
    final hasSel = state.mode == EditorMode.object
        ? state.selectedObjects.isNotEmpty
        : state.selVerts.isNotEmpty || state.selEdges.isNotEmpty || state.selFaces.isNotEmpty;
    if (hasSel) pivot = selectionPivot(state);
  }
  if (pivot == null) return [];
  final c = state.camera.project(pivot, size.width, size.height);
  if (c == null) return [];
  const len = 52.0;
  final out = <(int, Offset, Offset)>[];
  for (var a = 0; a < 3; a++) {
    final dir = a == 0 ? Vec3.unitX : a == 1 ? Vec3.unitY : Vec3.unitZ;
    final world = pivot + dir * state.camera.distance * 0.02;
    final p2 = state.camera.project(world, size.width, size.height);
    if (p2 == null) continue;
    final dx = p2.$1 - c.$1, dy = p2.$2 - c.$2;
    final l = dx * dx + dy * dy;
    if (l < 1e-6) continue;
    final scale = len / math.sqrt(l);
    out.add((a, Offset(c.$1, c.$2), Offset(c.$1 + dx * scale, c.$2 + dy * scale)));
  }
  return out;
}
