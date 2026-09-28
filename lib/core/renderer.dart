import 'dart:ui';

import 'camera.dart';
import 'scene.dart';
import 'vec3.dart';

enum ShadingMode { wireframe, solid, materialPreview }

/// A filled polygon ready to draw (already depth-sorted far to near).
class RenderPoly {
  final List<Offset> points;
  final Color color;
  final int objectIndex;
  final int faceIndex;
  final bool selected;
  final bool editTarget;

  RenderPoly({
    required this.points,
    required this.color,
    required this.objectIndex,
    required this.faceIndex,
    this.selected = false,
    this.editTarget = false,
  });
}

class RenderLine {
  final Offset a, b;
  final Color color;
  final double width;
  final bool dashed;

  RenderLine(this.a, this.b, this.color, {this.width = 1, this.dashed = false});
}

class RenderDot {
  final Offset at;
  final double radius;
  final Color color;

  RenderDot(this.at, this.radius, this.color);
}

/// Everything the viewport needs to draw for one frame, computed in pure
/// math so it can be asserted in tests without a canvas.
class RenderFrame {
  final List<RenderLine> grid = [];
  final List<RenderPoly> polys = [];
  final List<RenderLine> lines = []; // wireframe + edit overlays
  final List<RenderDot> dots = []; // vertices in edit mode
}

class _Tri {
  List<Offset> pts = [];
  double depth = 0;
  Color color = const Color(0x00000000);
  int object = 0, face = 0;
  bool selected = false, editTarget = false;
}

/// Turns a scene into draw primitives using a painter's-algorithm sort.
class SceneRenderer {
  final OrbitCamera camera;
  ShadingMode shading;
  bool showGrid;
  bool showAxes;
  bool wireframeOverlay;

  /// Edit-mode overlay state for the object being edited.
  int? editTargetIndex;
  Set<int> selVerts = {};
  Set<int> selEdges = {};
  Set<int> selFaces = {};
  Set<int> selectedObjects = {};

  SceneRenderer(
    this.camera, {
    this.shading = ShadingMode.solid,
    this.showGrid = true,
    this.showAxes = true,
    this.wireframeOverlay = true,
  });

  static const selectionColor = Color(0xFFFF8C42);
  static const activeColor = Color(0xFFFFB36B);
  static const vertexColor = Color(0xFF22262E);
  static const edgeColor = Color(0xFF9AA4B2);

  RenderFrame build(Scene scene, double width, double height) {
    final frame = RenderFrame();
    if (showGrid) _grid(frame, width, height);

    final tris = <_Tri>[];
    for (var oi = 0; oi < scene.objects.length; oi++) {
      final obj = scene.objects[oi];
      if (!obj.visible) continue;
      final isEdit = oi == editTargetIndex;
      final sel = selectedObjects.contains(oi);
      final mesh = obj.evaluatedMesh;
      final mat = obj.matrix;
      final world = mesh.vertices.map(mat.transformPoint).toList();

      // projected verts
      final proj = List<Offset?>.filled(world.length, null);
      final depths = List<double>.filled(world.length, 0);
      for (var i = 0; i < world.length; i++) {
        final p = camera.project(world[i], width, height);
        if (p != null) {
          proj[i] = Offset(p.$1, p.$2);
          depths[i] = p.$3;
        }
      }

      if (shading != ShadingMode.wireframe) {
        for (final (fi, tri) in mesh.triangulated()) {
          if (proj[tri[0]] == null || proj[tri[1]] == null || proj[tri[2]] == null) continue;
          final faceSel = isEdit && selFaces.contains(fi);
          final worldN = obj.matrix.transformDir(mesh.faceNormal(fi)).normalized();
          tris.add(_Tri()
            ..pts = [proj[tri[0]]!, proj[tri[1]]!, proj[tri[2]]!]
            ..depth = (depths[tri[0]] + depths[tri[1]] + depths[tri[2]]) / 3
            ..color = _shade(obj, worldN, faceSel, sel)
            ..object = oi
            ..face = fi
            ..selected = sel
            ..editTarget = isEdit);
        }
      }

      // wireframe: all edges (selected objects always get outlines)
      final drawWire = shading == ShadingMode.wireframe ||
          wireframeOverlay && shading != ShadingMode.wireframe ||
          sel || isEdit;
      if (drawWire) {
        final edges = mesh.allEdges().toList();
        for (var ei = 0; ei < edges.length; ei++) {
          final (a, b) = edges[ei];
          if (proj[a] == null || proj[b] == null) continue;
          final edgeSel = isEdit && selEdges.contains(ei);
          Color c;
          double w = 1;
          if (edgeSel) {
            c = selectionColor;
            w = 1.6;
          } else if (isEdit) {
            c = edgeColor.withValues(alpha: 0.85);
          } else if (sel) {
            c = selectionColor;
            w = 1.4;
          } else {
            c = const Color(0xFF000000).withValues(alpha: shading == ShadingMode.wireframe ? 0.9 : 0.28);
          }
          frame.lines.add(RenderLine(proj[a]!, proj[b]!, c, width: w));
        }
      }

      // edit-mode vertex dots
      if (isEdit) {
        for (var i = 0; i < world.length; i++) {
          final p = proj[i];
          if (p == null) continue;
          frame.dots.add(RenderDot(
            p,
            selVerts.contains(i) ? 4.5 : 3.5,
            selVerts.contains(i) ? selectionColor : vertexColor,
          ));
        }
      }
    }

    tris.sort((a, b) => b.depth.compareTo(a.depth));
    for (final t in tris) {
      frame.polys.add(RenderPoly(
        points: t.pts,
        color: t.color,
        objectIndex: t.object,
        faceIndex: t.face,
        selected: t.selected,
        editTarget: t.editTarget,
      ));
    }
    return frame;
  }

  void _grid(RenderFrame frame, double w, double h) {
    const extent = 10;
    for (var i = -extent; i <= extent; i++) {
      if (i == 0) continue;
      _gridLine(frame, Vec3(i.toDouble(), -extent.toDouble(), 0), Vec3(i.toDouble(), extent.toDouble(), 0), w, h, i % 10 == 0);
      _gridLine(frame, Vec3(-extent.toDouble(), i.toDouble(), 0), Vec3(extent.toDouble(), i.toDouble(), 0), w, h, i % 10 == 0);
    }
    if (showAxes) {
      _axisLine(frame, Vec3(-extent.toDouble(), 0, 0), Vec3(extent.toDouble(), 0, 0), const Color(0xFFB3454E), w, h);
      _axisLine(frame, Vec3(0, -extent.toDouble(), 0), Vec3(0, extent.toDouble(), 0), const Color(0xFF5B9A4F), w, h);
      _axisLine(frame, Vec3(0, 0, -extent.toDouble()), Vec3(0, 0, extent.toDouble()), const Color(0xFF4A6FA5), w, h);
    }
  }

  void _gridLine(RenderFrame f, Vec3 a, Vec3 b, double w, double h, bool major) {
    final pa = camera.project(a, w, h);
    final pb = camera.project(b, w, h);
    if (pa == null || pb == null) return;
    f.grid.add(RenderLine(
      Offset(pa.$1, pa.$2),
      Offset(pb.$1, pb.$2),
      Color(major ? 0xFF4A4A52 : 0xFF303035),
      width: major ? 1 : 0.5,
    ));
  }

  void _axisLine(RenderFrame f, Vec3 a, Vec3 b, Color c, double w, double h) {
    final pa = camera.project(a, w, h);
    final pb = camera.project(b, w, h);
    if (pa == null || pb == null) return;
    f.grid.add(RenderLine(Offset(pa.$1, pa.$2), Offset(pb.$1, pb.$2), c, width: 1.2));
  }

  Color _shade(SceneObject obj, Vec3 n, bool faceSel, bool objSel) {
    var base = obj.material.color;
    if (shading == ShadingMode.solid) {
      base = const Color(0xFF9BA1A8);
    }
    const light = Vec3(-0.45, -0.55, 0.7); // normalized-ish studio lamp
    final ndotl = n.dot(light.normalized()).abs();
    final diff = 0.35 + 0.65 * ndotl * (1 - obj.material.roughness * 0.4);
    var c = Color.fromARGB(
      255,
      (base.r * 255 * diff).clamp(0, 255).toInt(),
      (base.g * 255 * diff).clamp(0, 255).toInt(),
      (base.b * 255 * diff).clamp(0, 255).toInt(),
    );
    if (faceSel) {
      c = Color.lerp(c, selectionColor, 0.55)!;
    } else if (objSel) {
      c = Color.lerp(c, selectionColor, 0.15)!;
    }
    return c;
  }
}

