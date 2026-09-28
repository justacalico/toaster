import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'core/camera.dart';
import 'core/mesh.dart';
import 'core/modifiers.dart';
import 'core/ops.dart';
import 'core/picking.dart';
import 'core/primitives.dart';
import 'core/renderer.dart';
import 'core/scene.dart';
import 'core/serializer.dart';
import 'core/undo.dart';
import 'core/vec3.dart';

enum EditorMode { object, edit }

enum SelMode { vertex, edge, face }

enum Tool { select, move, rotate, scale }

enum TransformKind { grab, rotate, scale }

/// -1 = none, 0/1/2 = X/Y/Z.
typedef AxisLock = int;

class SceneSnapshot {
  final Scene scene;
  final Set<int> selectedObjects;
  final int? activeObject;
  final int? editTarget;
  final Set<int> selVerts, selEdges, selFaces;
  final EditorMode mode;

  SceneSnapshot(AppState s)
      : scene = s.scene.clone(),
        selectedObjects = Set.of(s.selectedObjects),
        activeObject = s.activeObject,
        editTarget = s.editTarget,
        selVerts = Set.of(s.selVerts),
        selEdges = Set.of(s.selEdges),
        selFaces = Set.of(s.selFaces),
        mode = s.mode;
}

/// In-progress G/R/S transform.
class TransformSession {
  final TransformKind kind;
  AxisLock axis = -1;
  final Vec3 pivot;
  Offset? startPointer;
  final double pivotDepth;
  final double viewportHeight;

  // start values
  final Map<int, Vec3> startLocations;
  final Map<int, Vec3> startRotations;
  final Map<int, Vec3> startScales;
  final Map<int, Vec3> startVerts; // edit mode: vert index -> position

  // readout for the status bar
  Vec3 transDelta = Vec3.zero;
  double rotAngle = 0;
  Vec3 scaleFactor = const Vec3(1, 1, 1);

  TransformSession({
    required this.kind,
    required this.pivot,
    this.startPointer,
    required this.pivotDepth,
    required this.viewportHeight,
    required this.startLocations,
    required this.startRotations,
    required this.startScales,
    required this.startVerts,
  });

  String get label {
    final axisName = axis < 0 ? '' : ' ${'XYZ'[axis]}';
    final value = switch (kind) {
      TransformKind.grab =>
        '(${transDelta.x.toStringAsFixed(2)}, ${transDelta.y.toStringAsFixed(2)}, ${transDelta.z.toStringAsFixed(2)})',
      TransformKind.rotate => '${(rotAngle * 180 / math.pi).toStringAsFixed(1)}°',
      TransformKind.scale =>
        '(${scaleFactor.x.toStringAsFixed(2)}, ${scaleFactor.y.toStringAsFixed(2)}, ${scaleFactor.z.toStringAsFixed(2)})',
    };
    return '${switch (kind) {
          TransformKind.grab => 'Move',
          TransformKind.rotate => 'Rotate',
          TransformKind.scale => 'Scale',
        }}$axisName $value';
  }
}

/// The one and only app state object (hard rule: lives above MaterialApp,
/// survives resizes).
class AppState extends ChangeNotifier {
  Scene scene = Scene();
  OrbitCamera camera = OrbitCamera();

  EditorMode mode = EditorMode.object;
  SelMode selMode = SelMode.face;
  Tool tool = Tool.select;
  ShadingMode shading = ShadingMode.solid;

  Set<int> selectedObjects = {};
  int? activeObject;

  int? editTarget;
  Set<int> selVerts = {};
  Set<int> selEdges = {};
  Set<int> selFaces = {};

  TransformSession? transform;
  SceneSnapshot? _preTransform;

  bool snapEnabled = false;
  double gridSize = 1.0;
  bool showOverlays = true;

  String? filePath;
  bool dirty = false;
  String statusHint = '';

  final UndoStack<SceneSnapshot> undoStack = UndoStack<SceneSnapshot>();

  List<String> savedScenes = []; // in-memory "recent files" names

  // ---------- helpers ----------

  SceneObject? get activeObj =>
      activeObject != null && activeObject! < scene.objects.length ? scene.objects[activeObject!] : null;

  SceneObject? get editObj =>
      editTarget != null && editTarget! < scene.objects.length ? scene.objects[editTarget!] : null;

  int get selectionCount =>
      mode == EditorMode.edit ? selVerts.length + selEdges.length + selFaces.length : selectedObjects.length;

  void markDirty() => dirty = true;

  /// Public repaint trigger for widgets that mutate plain objects
  /// (e.g. modifier fields) directly.
  void refresh() => notifyListeners();

  SceneSnapshot _snap() => SceneSnapshot(this);

  void _pushUndo() {
    undoStack.push(_snap());
    markDirty();
  }

  void _restore(SceneSnapshot s) {
    scene = s.scene;
    selectedObjects = s.selectedObjects;
    activeObject = s.activeObject;
    editTarget = s.editTarget;
    selVerts = s.selVerts;
    selEdges = s.selEdges;
    selFaces = s.selFaces;
    mode = s.mode;
    transform = null;
    _preTransform = null;
    notifyListeners();
  }

  void undo() {
    final s = undoStack.undo(_snap());
    if (s != null) _restore(s);
  }

  void redo() {
    final s = undoStack.redo(_snap());
    if (s != null) _restore(s);
  }

  void setHint(String h) {
    statusHint = h;
    notifyListeners();
  }

  // ---------- scene ops ----------

  void newScene() {
    _pushUndo();
    scene = Scene();
    selectedObjects.clear();
    activeObject = null;
    editTarget = null;
    _clearEditSel();
    mode = EditorMode.object;
    filePath = null;
    notifyListeners();
  }

  int addPrimitive(String name) {
    _pushUndo();
    final mesh = Primitives.build(name);
    final i = scene.add(SceneObject(name: name, mesh: mesh));
    selectedObjects
      ..clear()
      ..add(i);
    activeObject = i;
    if (mode == EditorMode.edit) exitEditMode();
    notifyListeners();
    return i;
  }

  void addMeshObject(String name, Mesh mesh) {
    _pushUndo();
    final i = scene.add(SceneObject(name: name, mesh: mesh));
    selectedObjects
      ..clear()
      ..add(i);
    activeObject = i;
    notifyListeners();
  }

  void deleteSelected() {
    if (mode == EditorMode.edit) {
      deleteEditSelection();
      return;
    }
    if (selectedObjects.isEmpty) return;
    _pushUndo();
    final doomed = Set.of(selectedObjects);
    final remaining = <SceneObject>[];
    final remap = List<int>.filled(scene.objects.length, -1);
    for (var i = 0; i < scene.objects.length; i++) {
      if (!doomed.contains(i)) {
        remap[i] = remaining.length;
        remaining.add(scene.objects[i]);
      }
    }
    scene.objects
      ..clear()
      ..addAll(remaining);
    selectedObjects.clear();
    activeObject = null;
    notifyListeners();
  }

  void duplicateSelected() {
    if (mode != EditorMode.object || selectedObjects.isEmpty) return;
    _pushUndo();
    final newSel = <int>{};
    for (final i in selectedObjects.toList()..sort()) {
      final c = scene.objects[i].clone();
      c.name = '${c.name}.001';
      c.location += const Vec3(0.5, 0.5, 0);
      newSel.add(scene.add(c));
    }
    selectedObjects = newSel;
    activeObject = newSel.last;
    notifyListeners();
  }

  /// Joins all selected objects into the active one.
  void joinSelected() {
    if (mode != EditorMode.object || activeObject == null || selectedObjects.length < 2) return;
    _pushUndo();
    final target = scene.objects[activeObject!];
    final inv = target.inverseMatrix;
    final doomed = <int>{};
    for (final i in selectedObjects) {
      if (i == activeObject) continue;
      final src = scene.objects[i];
      final m = inv * src.matrix;
      final base = target.mesh.vertices.length;
      for (final v in src.mesh.vertices) {
        target.mesh.vertices.add(m.transformPoint(v));
      }
      for (final f in src.mesh.faces) {
        target.mesh.faces.add(f.map((v) => v + base).toList());
      }
      for (final e in src.mesh.edges) {
        target.mesh.edges.add((e.$1 + base, e.$2 + base));
      }
      doomed.add(i);
    }
    final keep = <SceneObject>[];
    for (var i = 0; i < scene.objects.length; i++) {
      if (!doomed.contains(i)) keep.add(scene.objects[i]);
    }
    scene.objects
      ..clear()
      ..addAll(keep);
    activeObject = scene.objects.indexOf(target);
    selectedObjects = {activeObject!};
    notifyListeners();
  }

  // ---------- selection ----------

  void selectObject(int i, {bool additive = false}) {
    if (!additive) selectedObjects.clear();
    if (additive && selectedObjects.contains(i)) {
      selectedObjects.remove(i);
      if (activeObject == i) activeObject = selectedObjects.isEmpty ? null : selectedObjects.last;
    } else {
      selectedObjects.add(i);
      activeObject = i;
    }
    notifyListeners();
  }

  void selectAll() {
    if (mode == EditorMode.edit && editObj != null) {
      final m = editObj!.mesh;
      selVerts = List.generate(m.vertices.length, (i) => i).toSet();
      selEdges = List.generate(m.allEdges().length, (i) => i).toSet();
      selFaces = List.generate(m.faces.length, (i) => i).toSet();
    } else {
      selectedObjects = List.generate(scene.objects.length, (i) => i).toSet();
      activeObject = scene.objects.isEmpty ? null : scene.objects.length - 1;
    }
    notifyListeners();
  }

  void deselectAll() {
    if (mode == EditorMode.edit) {
      _clearEditSel();
    } else {
      selectedObjects.clear();
      activeObject = null;
    }
    notifyListeners();
  }

  void _clearEditSel() {
    selVerts = {};
    selEdges = {};
    selFaces = {};
  }

  // ---------- modes ----------

  void toggleEditMode() {
    if (mode == EditorMode.object) {
      enterEditMode();
    } else {
      exitEditMode();
    }
  }

  void enterEditMode() {
    if (mode == EditorMode.edit) return;
    final target = activeObject ?? (selectedObjects.isEmpty ? null : selectedObjects.first);
    if (target == null) {
      setHint('Select an object first');
      return;
    }
    _pushUndo();
    mode = EditorMode.edit;
    editTarget = target;
    selMode = SelMode.face;
    final m = scene.objects[target].mesh;
    selVerts = List.generate(m.vertices.length, (i) => i).toSet();
    selFaces = List.generate(m.faces.length, (i) => i).toSet();
    selEdges = List.generate(m.allEdges().length, (i) => i).toSet();
    notifyListeners();
  }

  void exitEditMode() {
    if (mode == EditorMode.object) return;
    _pushUndo();
    mode = EditorMode.object;
    _clearEditSel();
    if (editTarget != null) {
      selectedObjects = {editTarget!};
      activeObject = editTarget;
      editTarget = null;
    }
    notifyListeners();
  }

  void setSelMode(SelMode m) {
    if (selMode == m) return;
    selMode = m;
    notifyListeners();
  }

  void setTool(Tool t) {
    tool = t;
    notifyListeners();
  }

  void setShading(ShadingMode s) {
    shading = s;
    notifyListeners();
  }

  void cycleShading() {
    shading = ShadingMode.values[(shading.index + 1) % ShadingMode.values.length];
    notifyListeners();
  }

  void toggleSnap() {
    snapEnabled = !snapEnabled;
    notifyListeners();
  }

  void toggleOverlays() {
    showOverlays = !showOverlays;
    notifyListeners();
  }

  // ---------- picking ----------

  /// Click-selects in the viewport. Returns true if something was hit.
  bool pickAt(Offset pos, double width, double height, {bool additive = false}) {
    final (ro, rd) = camera.ray(pos.dx, pos.dy, width, height);
    if (mode == EditorMode.object) {
      final hit = pickObject(ro, rd, scene);
      if (hit == null) {
        if (!additive) deselectAll();
        return false;
      }
      selectObject(hit.$1, additive: additive);
      return true;
    }
    // edit mode element picking
    final obj = editObj;
    if (obj == null) return false;
    return _pickElement(pos, width, height, obj, ro, rd, additive: additive);
  }

  bool _pickElement(Offset pos, double w, double h, SceneObject obj, Vec3 ro, Vec3 rd,
      {bool additive = false}) {
    final mesh = obj.mesh;
    final mat = obj.matrix;
    switch (selMode) {
      case SelMode.vertex:
        var best = -1;
        var bestD = 144.0; // px^2 threshold
        for (var i = 0; i < mesh.vertices.length; i++) {
          final p = camera.project(mat.transformPoint(mesh.vertices[i]), w, h);
          if (p == null) continue;
          final d = (p.$1 - pos.dx) * (p.$1 - pos.dx) + (p.$2 - pos.dy) * (p.$2 - pos.dy);
          if (d < bestD) {
            bestD = d;
            best = i;
          }
        }
        if (best < 0) return false;
        _toggleIn(selVerts, best, additive);
        notifyListeners();
        return true;
      case SelMode.edge:
        final edges = mesh.allEdges().toList();
        var best = -1;
        var bestD = 144.0;
        for (var ei = 0; ei < edges.length; ei++) {
          final (a, b) = edges[ei];
          final pa = camera.project(mat.transformPoint(mesh.vertices[a]), w, h);
          final pb = camera.project(mat.transformPoint(mesh.vertices[b]), w, h);
          if (pa == null || pb == null) continue;
          final d = pointSegmentDist(pos.dx, pos.dy, pa.$1, pa.$2, pb.$1, pb.$2);
          if (d < bestD) {
            bestD = d;
            best = ei;
          }
        }
        if (best < 0) return false;
        _toggleIn(selEdges, best, additive);
        notifyListeners();
        return true;
      case SelMode.face:
        final hit = rayMesh(ro, rd, obj);
        if (hit == null) return false;
        _toggleIn(selFaces, hit.$2, additive);
        notifyListeners();
        return true;
    }
  }

  void _toggleIn(Set<int> set, int v, bool additive) {
    if (!additive) {
      set
        ..clear()
        ..add(v);
    } else if (!set.add(v)) {
      set.remove(v);
    }
  }

  // ---------- edit-mode ops ----------

  Set<int> _selectedVerts() {
    final obj = editObj;
    if (obj == null) return {};
    switch (selMode) {
      case SelMode.vertex:
        return Set.of(selVerts);
      case SelMode.edge:
        final all = obj.mesh.allEdges().toList();
        final out = <int>{};
        for (final ei in selEdges) {
          if (ei < all.length) {
            out.add(all[ei].$1);
            out.add(all[ei].$2);
          }
        }
        return out;
      case SelMode.face:
        final out = <int>{};
        for (final fi in selFaces) {
          if (fi < obj.mesh.faces.length) out.addAll(obj.mesh.faces[fi]);
        }
        return out;
    }
  }

  void extrude() {
    final obj = editObj;
    if (mode != EditorMode.edit || obj == null) return;
    if (selectionCount == 0) {
      setHint('Nothing selected');
      return;
    }
    _pushUndo();
    List<int> moved;
    switch (selMode) {
      case SelMode.face:
        if (selFaces.isEmpty) return;
        moved = MeshOps.extrudeFaces(obj.mesh, selFaces);
      case SelMode.edge:
        if (selEdges.isEmpty) return;
        moved = MeshOps.extrudeEdges(obj.mesh, selEdges);
      case SelMode.vertex:
        if (selVerts.isEmpty) return;
        moved = MeshOps.extrudeVertices(obj.mesh, selVerts);
    }
    selVerts = moved.toSet();
    selFaces.clear();
    selEdges.clear();
    selMode = SelMode.vertex;
    beginTransform(TransformKind.grab, null);
    notifyListeners();
  }

  void inset(double amount) {
    final obj = editObj;
    if (mode != EditorMode.edit || obj == null || selMode != SelMode.face || selFaces.isEmpty) {
      setHint('Inset needs selected faces');
      return;
    }
    _pushUndo();
    final inner = MeshOps.insetFaces(obj.mesh, selFaces, amount);
    // reselect: inner faces are the replaced faces (same indices)
    selVerts = inner.toSet();
    notifyListeners();
  }

  void subdivideSelected() {
    final obj = editObj;
    if (mode != EditorMode.edit || obj == null) return;
    _pushUndo();
    if (selMode == SelMode.face && selFaces.isNotEmpty) {
      final count = obj.mesh.faces.length;
      MeshOps.subdivide(obj.mesh, selFaces);
      // select the new faces
      selFaces = List.generate(obj.mesh.faces.length - count, (i) => count + i).toSet();
    } else if (selMode == SelMode.vertex && selVerts.isNotEmpty) {
      // subdivide edges touched by selected verts? Blender subdivides edges.
      final all = obj.mesh.allEdges().toList();
      final edgeIdx = <int>{};
      for (var i = 0; i < all.length; i++) {
        if (selVerts.contains(all[i].$1) && selVerts.contains(all[i].$2)) edgeIdx.add(i);
      }
      final created = MeshOps.subdivideEdges(obj.mesh, edgeIdx);
      selVerts = created;
    } else if (selMode == SelMode.edge && selEdges.isNotEmpty) {
      final created = MeshOps.subdivideEdges(obj.mesh, selEdges);
      selVerts = created;
      selMode = SelMode.vertex;
      selEdges.clear();
    }
    notifyListeners();
  }

  void fillFaces() {
    final obj = editObj;
    if (mode != EditorMode.edit || obj == null) return;
    final verts = _selectedVerts();
    if (verts.length < 3) {
      setHint('Need 3+ vertices to fill');
      return;
    }
    _pushUndo();
    final fi = MeshOps.fill(obj.mesh, verts);
    if (fi != null) {
      selFaces = {fi};
      selMode = SelMode.face;
    }
    notifyListeners();
  }

  void mergeByDistance([double dist = 0.001]) {
    final obj = editObj;
    if (mode != EditorMode.edit || obj == null) return;
    final verts = selMode == SelMode.vertex ? selVerts : _selectedVerts();
    if (verts.length < 2) {
      setHint('Need 2+ vertices to merge');
      return;
    }
    _pushUndo();
    final map = MeshOps.mergeByDistance(obj.mesh, verts, dist);
    selVerts = selVerts.map((v) => v < map.length ? map[v] : -1).where((v) => v >= 0).toSet();
    selFaces = {};
    selEdges = {};
    selMode = SelMode.vertex;
    notifyListeners();
  }

  void flipNormals() {
    final obj = editObj;
    if (mode != EditorMode.edit || obj == null) return;
    final faces = selMode == SelMode.face && selFaces.isNotEmpty
        ? selFaces
        : List.generate(obj.mesh.faces.length, (i) => i).toSet();
    _pushUndo();
    MeshOps.flipNormals(obj.mesh, faces);
    notifyListeners();
  }

  void deleteEditSelection() {
    final obj = editObj;
    if (mode != EditorMode.edit || obj == null) return;
    _pushUndo();
    switch (selMode) {
      case SelMode.face:
        MeshOps.deleteFaces(obj.mesh, selFaces);
        selFaces = {};
      case SelMode.edge:
        MeshOps.deleteEdges(obj.mesh, selEdges);
        selEdges = {};
      case SelMode.vertex:
        MeshOps.deleteVertices(obj.mesh, selVerts);
        selVerts = {};
        selEdges = {};
        selFaces = {};
    }
    notifyListeners();
  }

  void toggleSmoothShading() {
    if (mode == EditorMode.object) {
      if (selectedObjects.isEmpty) return;
      _pushUndo();
      for (final i in selectedObjects) {
        scene.objects[i].smoothShading = !scene.objects[i].smoothShading;
      }
    } else if (editObj != null) {
      _pushUndo();
      editObj!.smoothShading = !editObj!.smoothShading;
    }
    notifyListeners();
  }

  // ---------- transforms ----------

  Vec3 get _selectionPivot {
    if (mode == EditorMode.edit) {
      final obj = editObj;
      if (obj == null) return Vec3.zero;
      final verts = _selectedVerts();
      if (verts.isEmpty) return obj.worldCenter;
      var c = Vec3.zero;
      for (final v in verts) {
        c += obj.matrix.transformPoint(obj.mesh.vertices[v]);
      }
      return c / verts.length.toDouble();
    }
    if (selectedObjects.isEmpty) return Vec3.zero;
    var c = Vec3.zero;
    for (final i in selectedObjects) {
      c += scene.objects[i].location;
    }
    return c / selectedObjects.length.toDouble();
  }

  /// Starts a G/R/S session. [pointer] is the current pointer pos; pass
  /// null when invoked from a hotkey before the pointer moves.
  void beginTransform(TransformKind kind, Offset? pointer,
      {double viewportHeight = 600, double pivotDepth = -1, AxisLock axis = -1}) {
    if (mode == EditorMode.edit && _selectedVerts().isEmpty) {
      setHint('Nothing selected');
      return;
    }
    if (mode == EditorMode.object && selectedObjects.isEmpty) {
      setHint('Nothing selected');
      return;
    }
    _preTransform = _snap();
    final pivot = _selectionPivot;
    final startLocs = <int, Vec3>{};
    final startRots = <int, Vec3>{};
    final startScales = <int, Vec3>{};
    final startVerts = <int, Vec3>{};
    if (mode == EditorMode.edit) {
      final obj = editObj!;
      for (final v in _selectedVerts()) {
        startVerts[v] = obj.mesh.vertices[v];
      }
    } else {
      for (final i in selectedObjects) {
        final o = scene.objects[i];
        startLocs[i] = o.location;
        startRots[i] = o.rotation;
        startScales[i] = o.scale;
      }
    }
    transform = TransformSession(
      kind: kind,
      pivot: pivot,
      startPointer: pointer,
      pivotDepth: pivotDepth,
      viewportHeight: viewportHeight,
      startLocations: startLocs,
      startRotations: startRots,
      startScales: startScales,
      startVerts: startVerts,
    )..axis = axis;
    notifyListeners();
  }

  void constrainAxis(AxisLock a) {
    transform?.axis = transform?.axis == a ? -1 : a;
    notifyListeners();
  }

  /// Applies the current pointer position to the session.
  void updateTransform(Offset pointer) {
    final t = transform;
    if (t == null) return;
    if (t.startPointer == null) {
      t.startPointer = pointer;
      return;
    }
    final dx = pointer.dx - t.startPointer!.dx;
    final dy = pointer.dy - t.startPointer!.dy;
    switch (t.kind) {
      case TransformKind.grab:
        var delta = camera.screenDeltaToWorld(dx, dy, t.viewportHeight,
            t.pivotDepth > 0 ? t.pivotDepth : camera.distance);
        if (t.axis >= 0) {
          final a = Vec3(t.axis == 0 ? 1 : 0, t.axis == 1 ? 1 : 0, t.axis == 2 ? 1 : 0);
          delta = a * delta.dot(a);
        }
        if (snapEnabled) {
          delta = Vec3(
            (delta.x / gridSize).roundToDouble() * gridSize,
            (delta.y / gridSize).roundToDouble() * gridSize,
            (delta.z / gridSize).roundToDouble() * gridSize,
          );
        }
        t.transDelta = delta;
        _applyTranslate(t, delta);
      case TransformKind.rotate:
        var angle = dx * 0.0125;
        if (snapEnabled) {
          angle = (angle * 180 / math.pi / 5).roundToDouble() * 5 * math.pi / 180;
        }
        t.rotAngle = angle;
        final axis = t.axis >= 0
            ? Vec3(t.axis == 0 ? 1 : 0, t.axis == 1 ? 1 : 0, t.axis == 2 ? 1 : 0)
            : camera.forward;
        _applyRotate(t, axis, angle);
      case TransformKind.scale:
        var f = math.exp(dx * 0.004).toDouble();
        if (snapEnabled) {
          f = (f * 10).roundToDouble() / 10;
        }
        t.scaleFactor = t.axis >= 0 ? const Vec3(1, 1, 1).withAxis(t.axis, f) : Vec3(f, f, f);
        _applyScale(t, t.scaleFactor);
    }
    notifyListeners();
  }

  void _applyTranslate(TransformSession t, Vec3 worldDelta) {
    if (mode == EditorMode.edit) {
      final obj = editObj!;
      final local = obj.inverseMatrix.transformDir(worldDelta);
      for (final e in t.startVerts.entries) {
        obj.mesh.vertices[e.key] = e.value + local;
      }
    } else {
      for (final e in t.startLocations.entries) {
        scene.objects[e.key].location = e.value + worldDelta;
      }
    }
  }

  void _applyRotate(TransformSession t, Vec3 axis, double angle) {
    final mat = Mat4.translation(t.pivot) *
        Mat4.rotationAxis(axis.normalized(), angle) *
        Mat4.translation(-t.pivot);
    if (mode == EditorMode.edit) {
      final obj = editObj!;
      final total = obj.inverseMatrix * mat * obj.matrix;
      for (final e in t.startVerts.entries) {
        obj.mesh.vertices[e.key] = total.transformPoint(e.value);
      }
    } else {
      for (final i in t.startLocations.keys) {
        final o = scene.objects[i];
        o.location = mat.transformPoint(t.startLocations[i]!);
        final rm = Mat4.rotationZ(t.startRotations[i]!.z) *
            Mat4.rotationY(t.startRotations[i]!.y) *
            Mat4.rotationX(t.startRotations[i]!.x);
        final rm2 = Mat4.rotationAxis(axis.normalized(), angle) * rm;
        o.rotation = _eulerFromMat(rm2);
      }
    }
  }

  void _applyScale(TransformSession t, Vec3 factor) {
    final s = Mat4.scaling(factor);
    final mat = Mat4.translation(t.pivot) * s * Mat4.translation(-t.pivot);
    if (mode == EditorMode.edit) {
      final obj = editObj!;
      final total = obj.inverseMatrix * mat * obj.matrix;
      for (final e in t.startVerts.entries) {
        obj.mesh.vertices[e.key] = total.transformPoint(e.value);
      }
    } else {
      for (final i in t.startLocations.keys) {
        final o = scene.objects[i];
        o.location = mat.transformPoint(t.startLocations[i]!);
        o.scale = t.startScales[i]!.mulVec(factor);
      }
    }
  }

  static Vec3 _eulerFromMat(Mat4 m) {
    final sy = (-m.m[8]).clamp(-1.0, 1.0);
    final y = math.asin(sy);
    double x, z;
    if (sy.abs() < 0.9999) {
      x = math.atan2(m.m[9], m.m[10]);
      z = math.atan2(m.m[4], m.m[0]);
    } else {
      x = math.atan2(-m.m[6], m.m[5]);
      z = 0;
    }
    return Vec3(x, y, z);
  }

  void confirmTransform() {
    if (transform == null) return;
    if (_preTransform != null) {
      undoStack.push(_preTransform!);
      markDirty();
    }
    transform = null;
    _preTransform = null;
    notifyListeners();
  }

  void cancelTransform() {
    if (_preTransform != null) {
      final s = _preTransform!;
      transform = null;
      _preTransform = null;
      _restore(s);
    } else {
      transform = null;
      notifyListeners();
    }
  }

  // ---------- object properties ----------

  void setActiveName(String name) {
    final o = activeObj;
    if (o == null || name.isEmpty) return;
    _pushUndo();
    o.name = name;
    notifyListeners();
  }

  void setActiveLocation(Vec3 v) {
    final o = activeObj;
    if (o == null) return;
    _pushUndo();
    o.location = v;
    notifyListeners();
  }

  void setActiveRotation(Vec3 v) {
    final o = activeObj;
    if (o == null) return;
    _pushUndo();
    o.rotation = v;
    notifyListeners();
  }

  void setActiveScale(Vec3 v) {
    final o = activeObj;
    if (o == null) return;
    _pushUndo();
    o.scale = v;
    notifyListeners();
  }

  void setActiveColor(Color c) {
    final o = activeObj;
    if (o == null) return;
    _pushUndo();
    o.material.color = c;
    notifyListeners();
  }

  void setActiveMetallic(double v) {
    final o = activeObj;
    if (o == null) return;
    _pushUndo();
    o.material.metallic = v;
    notifyListeners();
  }

  void setActiveRoughness(double v) {
    final o = activeObj;
    if (o == null) return;
    _pushUndo();
    o.material.roughness = v;
    notifyListeners();
  }

  void setObjectVisible(int i, bool v) {
    if (i >= scene.objects.length) return;
    _pushUndo();
    scene.objects[i].visible = v;
    notifyListeners();
  }

  // ---------- modifiers ----------

  void addModifier(String type) {
    final o = activeObj;
    if (o == null) return;
    _pushUndo();
    o.modifiers.add(switch (type) {
      'mirror' => MirrorModifier(),
      'array' => ArrayModifier(),
      'subdivision' => SubdivisionModifier(),
      'bevel' => BevelModifier(),
      'solidify' => SolidifyModifier(),
      _ => throw ArgumentError(type),
    });
    notifyListeners();
  }

  void removeModifier(int objIdx, int modIdx) {
    if (objIdx >= scene.objects.length) return;
    final mods = scene.objects[objIdx].modifiers;
    if (modIdx >= mods.length) return;
    _pushUndo();
    mods.removeAt(modIdx);
    notifyListeners();
  }

  void moveModifier(int objIdx, int modIdx, int dir) {
    if (objIdx >= scene.objects.length) return;
    final mods = scene.objects[objIdx].modifiers;
    final target = modIdx + dir;
    if (modIdx < 0 || target < 0 || modIdx >= mods.length || target >= mods.length) return;
    _pushUndo();
    final m = mods.removeAt(modIdx);
    mods.insert(target, m);
    notifyListeners();
  }

  /// Bakes the modifier at [modIdx] into the mesh, evaluated on top of the
  /// modifiers above it in the stack (like Blender's Apply). The applied
  /// modifier leaves the stack; the ones above stay live.
  void applyModifier(int objIdx, int modIdx) {
    if (objIdx >= scene.objects.length) return;
    final o = scene.objects[objIdx];
    if (modIdx < 0 || modIdx >= o.modifiers.length) return;
    _pushUndo();
    var m = o.mesh;
    for (var i = 0; i <= modIdx; i++) {
      if (o.modifiers[i].enabled) m = o.modifiers[i].apply(m);
    }
    o.modifiers.removeAt(modIdx);
    o.mesh = m;
    notifyListeners();
  }

  void applyAllModifiers(int objIdx) {
    if (objIdx >= scene.objects.length) return;
    final o = scene.objects[objIdx];
    if (o.modifiers.isEmpty) return;
    _pushUndo();
    o.mesh = o.evaluatedMesh;
    o.modifiers.clear();
    notifyListeners();
  }

  // ---------- camera / view ----------

  void setViewPreset(String name) {
    camera.setView(name);
    notifyListeners();
  }

  void togglePerspective() {
    camera.togglePerspective();
    notifyListeners();
  }

  void frameSelected(double aspect) {
    if (mode == EditorMode.edit) {
      final obj = editObj;
      if (obj == null) return;
      final verts = _selectedVerts();
      if (verts.isEmpty) return;
      var lo = obj.matrix.transformPoint(obj.mesh.vertices[verts.first]);
      var hi = lo;
      for (final v in verts) {
        final w = obj.matrix.transformPoint(obj.mesh.vertices[v]);
        lo = lo.min(w);
        hi = hi.max(w);
      }
      camera.frame(lo, hi, aspect);
    } else {
      if (selectedObjects.isEmpty) {
        // frame all
        if (scene.objects.isEmpty) return;
        var lo = Vec3(double.infinity, double.infinity, double.infinity);
        var hi = -lo;
        for (final o in scene.objects) {
          if (!o.visible) continue;
          final (oLo, oHi) = o.evaluatedMesh.bounds;
          final wLo = o.matrix.transformPoint(oLo);
          final wHi = o.matrix.transformPoint(oHi);
          lo = lo.min(wLo.min(wHi));
          hi = hi.max(wLo.max(wHi));
        }
        if (lo.x.isInfinite) return;
        camera.frame(lo, hi, aspect);
      } else {
        var lo = Vec3(double.infinity, double.infinity, double.infinity);
        var hi = -lo;
        for (final i in selectedObjects) {
          final o = scene.objects[i];
          final (oLo, oHi) = o.evaluatedMesh.bounds;
          final pts = [
            for (final x in [oLo.x, oHi.x])
              for (final y in [oLo.y, oHi.y])
                for (final z in [oLo.z, oHi.z]) o.matrix.transformPoint(Vec3(x, y, z))
          ];
          for (final p in pts) {
            lo = lo.min(p);
            hi = hi.max(p);
          }
        }
        camera.frame(lo, hi, aspect);
      }
    }
    notifyListeners();
  }

  // ---------- persistence ----------

  String saveSceneText() => Serializer.encode(scene);

  void loadSceneText(String text) {
    _pushUndo();
    scene = Serializer.decode(text);
    selectedObjects.clear();
    activeObject = null;
    editTarget = null;
    _clearEditSel();
    mode = EditorMode.object;
    markDirty();
    notifyListeners();
  }

  String exportObj() => Serializer.toObj(scene);

  void importObj(String text) {
    final mesh = Serializer.fromObj(text);
    if (mesh.vertices.isEmpty) {
      setHint('No geometry found');
      return;
    }
    addMeshObject('Imported', mesh);
  }
}
