import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:toaster/app_state.dart';
import 'package:toaster/core/camera.dart';
import 'package:toaster/core/mesh.dart';
import 'package:toaster/core/modifiers.dart';
import 'package:toaster/core/ops.dart';
import 'package:toaster/core/primitives.dart';
import 'package:toaster/core/scene.dart';
import 'package:toaster/core/undo.dart';
import 'package:toaster/core/vec3.dart';
import 'package:toaster/ui/viewport_painter.dart';

void main() {
  group('edge cases', () {
    test('ortho camera projection', () {
      final c = OrbitCamera(perspective: false);
      final p = c.project(Vec3.zero, 800, 600);
      expect(p, isNotNull);
      expect(c.clone().perspective, isFalse);
    });

    test('mesh compact remaps loose edges and drops degenerate faces', () {
      final m = Mesh(
        vertices: [Vec3.zero, const Vec3(1, 0, 0), const Vec3(0, 1, 0)],
        faces: [
          [0, 1, 2],
          [0, 1, 0], // first == last -> trailing dup removed then dropped as degenerate
        ],
        edges: [(1, 2), (2, 1), (0, 0)],
      );
      m.weld(0.001);
      expect(m.vertices.length, 3);
      // edges were remapped/normalized, self-edge dropped
      for (final e in m.edges) {
        expect(e.$1, isNot(e.$2));
        expect(e.$1, lessThan(e.$2));
      }
    });

    test('mirror merges on-plane loose edges', () {
      final m = Mesh(
        vertices: [Vec3.zero, const Vec3(1, 0, 0), const Vec3(0, 0, 1)],
        edges: [(0, 1), (0, 2)],
      );
      final out = MirrorModifier(axis: 0, merge: true, mergeDistance: 0.01).apply(m);
      // edge (0,1): vert1 at x=1 mirrors; edge (0,2) both on plane, not mirrored
      expect(out.edges.length, 3); // 2 originals + 1 mirrored
    });

    test('array copies loose edges per iteration', () {
      final m = Mesh(
        vertices: [Vec3.zero, const Vec3(1, 0, 0)],
        edges: [(0, 1)],
      );
      final out = ArrayModifier(count: 3).apply(m);
      expect(out.edges.length, 3);
    });

    test('scene json edge ordering normalized and defaults', () {
      final j = <String, dynamic>{
        'objects': [
          {
            'name': 'w',
            'vertices': [
              [0, 0, 0],
              [1, 0, 0],
              [0, 0, 1],
            ],
            'faces': [
              [0, 1, 2]
            ],
            'edges': [
              [2, 0],
              [1, 0],
            ],
          },
          {
            'name': 'bare',
            'vertices': [
              [0, 0, 0]
            ],
            'faces': <List<int>>[],
          },
        ]
      };
      final s = Scene.fromJson(j);
      final m = s.objects.first.mesh;
      expect(m.edges, containsAll([(0, 2), (0, 1)]));
      expect(s.objects[1].mesh.edges, isEmpty);
      // missing modifiers -> default empty; missing backgroundColor -> default
      expect(s.objects.first.modifiers, isEmpty);
      expect(s.backgroundColor.toARGB32(), 0xFF1E1E22);
      // objects key absent entirely
      expect(Scene.fromJson(const <String, dynamic>{}).objects, isEmpty);
    });

    test('undo stack redoCount', () {
      final u = UndoStack<int>();
      u.push(1);
      u.push(2);
      expect(u.redoCount, 0);
      u.undo(3);
      expect(u.redoCount, 1);
    });

    test('gizmoSegments edit-mode pivots and behind-camera', () {
      final s = AppState();
      s.scene.add(SceneObject(name: 'C', mesh: Primitives.cube()));
      s.selectObject(0);
      s.enterEditMode();
      s.setSelMode(SelMode.vertex);
      s.selVerts = {0, 1};
      var segs = gizmoSegments(s, const Size(800, 600));
      expect(segs.length, 3); // move tool -> 3 axis arms
      s.setSelMode(SelMode.face);
      s.selFaces = {0, 1};
      segs = gizmoSegments(s, const Size(800, 600));
      expect(segs.length, 3);
      // edge mode pivots on shared verts
      s.setSelMode(SelMode.edge);
      s.selEdges = {0};
      segs = gizmoSegments(s, const Size(800, 600));
      expect(segs.length, 3);
      // pivot behind camera -> empty
      s.camera.target = const Vec3(0, 0, -40);
      segs = gizmoSegments(s, const Size(800, 600));
      expect(segs, isEmpty);
      // no selection -> empty
      s.camera.target = Vec3.zero;
      s.selEdges = {};
      s.exitEditMode();
      s.deselectAll();
      expect(gizmoSegments(s, const Size(800, 600)), isEmpty);
    });

    test('join keeps unselected objects and copies loose edges', () {
      final s = AppState();
      s.scene.add(SceneObject(name: 'a', mesh: Primitives.cube()));
      s.scene.add(SceneObject(
        name: 'w',
        mesh: Mesh(vertices: [Vec3.zero, const Vec3(1, 0, 0)], edges: [(0, 1)]),
      ));
      s.scene.add(SceneObject(name: 'kept', mesh: Primitives.plane()));
      s.selectedObjects = {0, 1};
      s.activeObject = 0;
      s.joinSelected();
      expect(s.scene.objects.length, 2);
      expect(s.scene.objects.map((o) => o.name), contains('kept'));
      expect(s.scene.objects[0].mesh.edges.length, 1);
    });

    test('flipNormals with non-face selection flips everything', () {
      final s = AppState();
      s.scene.add(SceneObject(name: 'a', mesh: Primitives.cube()));
      s.selectObject(0);
      s.enterEditMode();
      s.setSelMode(SelMode.vertex);
      s.selVerts = {0};
      s.flipNormals();
      expect(s.editObj!.mesh.faceNormal(1).z, -1);
    });

    test('beginTransform in edit mode with empty selection warns', () {
      final s = AppState();
      s.scene.add(SceneObject(name: 'a', mesh: Primitives.cube()));
      s.selectObject(0);
      s.enterEditMode();
      s.deselectAll();
      s.beginTransform(TransformKind.grab, const Offset(0, 0));
      expect(s.transform, isNull);
      expect(s.statusHint, 'Nothing selected');
    });

    test('edge-mode selection supplies verts to transform', () {
      final s = AppState();
      s.scene.add(SceneObject(name: 'a', mesh: Primitives.cube()));
      s.selectObject(0);
      s.enterEditMode();
      s.setSelMode(SelMode.edge);
      s.selEdges = {0};
      final before = s.editObj!.mesh.vertices[0];
      s.beginTransform(TransformKind.grab, const Offset(400, 300), viewportHeight: 600);
      s.updateTransform(const Offset(430, 300));
      s.confirmTransform();
      expect(s.editObj!.mesh.vertices[0].distanceTo(before), greaterThan(0));
    });

    test('delete keeps unselected objects', () {
      final s = AppState();
      s.scene.add(SceneObject(name: 'a', mesh: Primitives.cube()));
      s.scene.add(SceneObject(name: 'b', mesh: Primitives.cube()));
      s.selectObject(0);
      s.deleteSelected();
      expect(s.scene.objects.single.name, 'b');
      // selections remapped: nothing selected now
      expect(s.selectedObjects, isEmpty);
    });

    test('selectObject in edit mode moves the edit target', () {
      final s = AppState();
      s.scene.add(SceneObject(name: 'a', mesh: Primitives.cube()));
      s.scene.add(SceneObject(name: 'b', mesh: Primitives.plane()));
      s.selectObject(0);
      s.enterEditMode();
      expect(s.editTarget, 0);
      s.selectObject(1); // non-additive: switches edit target
      expect(s.mode, EditorMode.edit);
      expect(s.editTarget, 1);
      // additive pick keeps the same target
      s.selectObject(0, additive: true);
      expect(s.editTarget, 1);
    });

    test('deleteEditSelection with empty selection hints', () {
      final s = AppState();
      s.scene.add(SceneObject(name: 'a', mesh: Primitives.cube()));
      s.selectObject(0);
      s.enterEditMode();
      s.deselectAll();
      s.deleteSelected();
      expect(s.statusHint, 'Nothing selected');
      expect(s.editObj!.mesh.vertices.length, 8);
    });

    test('deleteVertices remaps loose edges', () {
      final m = Mesh(
        vertices: [Vec3.zero, const Vec3(1, 0, 0), const Vec3(0, 1, 0), const Vec3(0, 0, 1)],
        edges: [(1, 2), (2, 3)],
      );
      MeshOps.deleteVertices(m, {0});
      expect(m.vertices.length, 3);
      expect(m.edges, containsAll([(0, 1), (1, 2)]));
    });

    test('rotation extraction gimbal branch (90 deg pitch)', () {
      final s = AppState();
      s.scene.add(SceneObject(name: 'a', mesh: Primitives.cube())
        ..rotation = const Vec3(0, 1.5707963, 0));
      s.selectObject(0);
      s.beginTransform(TransformKind.rotate, const Offset(400, 300), viewportHeight: 600);
      s.updateTransform(const Offset(400, 300)); // zero delta: rm2 stays at 90 deg pitch
      s.confirmTransform();
      expect(s.transform, isNull);
    });
  });
}

