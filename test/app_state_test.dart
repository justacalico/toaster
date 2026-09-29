import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:toaster/app_state.dart';
import 'package:toaster/core/primitives.dart';
import 'package:toaster/core/renderer.dart';
import 'package:toaster/core/scene.dart';
import 'package:toaster/core/vec3.dart';

AppState state({bool cube = true}) {
  final s = AppState();
  if (cube) {
    s.scene.add(SceneObject(name: 'Cube', mesh: Primitives.cube()));
    s.selectObject(0);
  }
  return s;
}

void main() {
  group('scene ops', () {
    test('addPrimitive selects the new object', () {
      final s = state(cube: false);
      final i = s.addPrimitive('Cube');
      expect(i, 0);
      expect(s.selectedObjects, {0});
      expect(s.activeObject, 0);
      for (final name in Primitives.names) {
        s.addPrimitive(name);
      }
      expect(s.scene.objects.length, 11);
    });

    test('addMeshObject', () {
      final s = state(cube: false);
      s.addMeshObject('X', Primitives.plane());
      expect(s.scene.objects.single.name, 'X');
    });

    test('deleteSelected removes objects', () {
      final s = state();
      s.addPrimitive('Plane');
      s.selectedObjects = {0, 1};
      s.deleteSelected();
      expect(s.scene.objects, isEmpty);
      expect(s.activeObject, isNull);
    });

    test('deleteSelected with empty selection is a no-op', () {
      final s = state();
      s.deselectAll();
      final n = s.undoStack.undoCount;
      s.deleteSelected();
      expect(s.undoStack.undoCount, n);
    });

    test('duplicateSelected clones with offset', () {
      final s = state();
      s.duplicateSelected();
      expect(s.scene.objects.length, 2);
      expect(s.scene.objects[1].name, 'Cube.001');
      expect(s.scene.objects[1].location, const Vec3(0.5, 0.5, 0));
      expect(s.activeObject, 1);
      // no-op in edit mode
      s.enterEditMode();
      s.duplicateSelected();
      expect(s.scene.objects.length, 2);
    });

    test('joinSelected merges meshes into active', () {
      final s = state();
      s.addPrimitive('Plane');
      s.selectedObjects = {0, 1};
      s.activeObject = 0;
      s.joinSelected();
      expect(s.scene.objects.length, 1);
      expect(s.scene.objects[0].mesh.faces.length, 7);
      // needs >= 2 selected
      s.joinSelected();
      expect(s.scene.objects.length, 1);
    });

    test('newScene clears everything', () {
      final s = state();
      s.filePath = 'x.toast';
      s.newScene();
      expect(s.scene.objects, isEmpty);
      expect(s.selectedObjects, isEmpty);
      expect(s.filePath, isNull);
    });
  });

  group('selection', () {
    test('selectObject additive toggles', () {
      final s = state();
      s.addPrimitive('Cube'); // selects {1}
      s.selectObject(0, additive: true);
      expect(s.selectedObjects, {0, 1});
      s.selectObject(0, additive: true);
      expect(s.selectedObjects, {1});
      expect(s.activeObject, 1);
    });

    test('selectAll / deselectAll', () {
      final s = state();
      s.addPrimitive('Cube');
      s.selectAll();
      expect(s.selectedObjects.length, 2);
      s.deselectAll();
      expect(s.selectedObjects, isEmpty);
      expect(s.activeObject, isNull);
    });

    test('pickAt selects object under ray', () {
      final s = state();
      // camera default looks at origin where the cube sits
      final hit = s.pickAt(const Offset(400, 300), 800, 600);
      expect(hit, isTrue);
      expect(s.selectedObjects, {0});
    });

    test('pickAt empty space deselects', () {
      final s = state();
      final hit = s.pickAt(const Offset(10, 10), 800, 600);
      expect(hit, isFalse);
      expect(s.selectedObjects, isEmpty);
    });

    test('pickAt additive toggles selection', () {
      final s = state();
      s.deselectAll();
      s.pickAt(const Offset(400, 300), 800, 600, additive: true);
      expect(s.selectedObjects, {0});
      s.pickAt(const Offset(400, 300), 800, 600, additive: true);
      expect(s.selectedObjects, isEmpty);
    });
  });

  group('edit mode', () {
    test('enterEditMode selects all elements', () {
      final s = state();
      s.enterEditMode();
      expect(s.mode, EditorMode.edit);
      expect(s.editTarget, 0);
      expect(s.selVerts.length, 8);
      expect(s.selFaces.length, 6);
      expect(s.selEdges.length, 12);
    });

    test('enterEditMode without selection hints', () {
      final s = state(cube: false);
      s.enterEditMode();
      expect(s.mode, EditorMode.object);
      expect(s.statusHint, isNotEmpty);
    });

    test('toggleEditMode round trip preserves selection', () {
      final s = state();
      s.toggleEditMode();
      expect(s.mode, EditorMode.edit);
      s.toggleEditMode();
      expect(s.mode, EditorMode.object);
      expect(s.selectedObjects, {0});
      // second enter is idempotent
      s.exitEditMode();
      expect(s.mode, EditorMode.object);
    });

    test('sel mode switching', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.edge);
      expect(s.selMode, SelMode.edge);
      s.setSelMode(SelMode.edge); // idempotent
      expect(s.selMode, SelMode.edge);
    });

    test('edit pick selects vertex', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.vertex);
      s.deselectAll();
      // project a vert and click its position
      final obj = s.editObj!;
      final wp = obj.matrix.transformPoint(obj.mesh.vertices[0]);
      final p = s.camera.project(wp, 800, 600)!;
      expect(s.pickAt(Offset(p.$1, p.$2), 800, 600), isTrue);
      expect(s.selVerts, {0});
    });

    test('edit pick vertex misses far clicks', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.vertex);
      s.deselectAll();
      expect(s.pickAt(const Offset(5, 5), 800, 600), isFalse);
    });

    test('edit pick edge', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.edge);
      s.deselectAll();
      final obj = s.editObj!;
      final (a, b) = obj.mesh.allEdges().first;
      final mid = (obj.mesh.vertices[a] + obj.mesh.vertices[b]) / 2;
      final p = s.camera.project(obj.matrix.transformPoint(mid), 800, 600)!;
      expect(s.pickAt(Offset(p.$1, p.$2), 800, 600), isTrue);
      expect(s.selEdges, isNotEmpty);
      expect(s.pickAt(const Offset(5, 5), 800, 600), isFalse);
    });

    test('edit pick face', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.face);
      s.deselectAll();
      // click center of the top face
      final obj = s.editObj!;
      final c = obj.mesh.faceCenter(1);
      final p = s.camera.project(obj.matrix.transformPoint(c), 800, 600)!;
      expect(s.pickAt(Offset(p.$1, p.$2), 800, 600), isTrue);
      expect(s.selFaces, {1});
      // additive toggles off
      s.pickAt(Offset(p.$1, p.$2), 800, 600, additive: true);
      expect(s.selFaces, isEmpty);
      expect(s.pickAt(const Offset(5, 5), 800, 600), isFalse);
    });

    test('selectAll in edit mode selects elements', () {
      final s = state();
      s.enterEditMode();
      s.deselectAll();
      s.selectAll();
      expect(s.selVerts.length, 8);
    });
  });

  group('edit ops', () {
    test('extrude faces begins a grab session', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.face);
      s.selFaces = {1};
      s.extrude();
      expect(s.editObj!.mesh.faces.length, 10);
      expect(s.transform, isNotNull);
      expect(s.transform!.kind, TransformKind.grab);
      expect(s.selVerts.length, 4);
    });

    test('extrude edges', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.edge);
      s.deselectAll();
      s.selEdges = {0};
      s.extrude();
      expect(s.editObj!.mesh.faces.length, 7);
    });

    test('extrude vertices', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.vertex);
      s.deselectAll();
      s.selVerts = {0};
      s.extrude();
      expect(s.editObj!.mesh.edges.length, 1);
    });

    test('extrude nothing selected warns', () {
      final s = state();
      s.enterEditMode();
      s.deselectAll();
      s.extrude();
      expect(s.statusHint, 'Nothing selected');
      // not in edit mode at all
      s.exitEditMode();
      s.extrude();
      expect(s.transform, isNull);
    });

    test('extrude empty set in a mode warns', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.face);
      s.selFaces = {};
      s.selVerts = {};
      s.selEdges = {};
      s.extrude();
      expect(s.statusHint, 'Nothing selected');
    });

    test('inset shrinks the face', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.face);
      s.selFaces = {1};
      final before = s.editObj!.mesh.faces.length;
      s.inset(0.3);
      expect(s.editObj!.mesh.faces.length, before + 4);
    });

    test('inset requires face selection', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.vertex);
      s.selVerts = {0};
      s.inset(0.3);
      expect(s.statusHint, 'Inset needs selected faces');
    });

    test('subdivide faces', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.face);
      s.selFaces = {1};
      s.subdivideSelected();
      expect(s.editObj!.mesh.faces.length, 9);
      expect(s.selFaces.length, 4);
    });

    test('subdivide edges', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.edge);
      s.deselectAll();
      s.selEdges = {0};
      s.subdivideSelected();
      expect(s.selMode, SelMode.vertex);
      expect(s.selVerts.length, 1);
    });

    test('subdivide verts subdivides their shared edge', () {
      final s = state();
      s.enterEditMode();
      // enterEditMode selected everything; vert-mode with all verts selected
      // subdivides all 12 face edges -> 12 new verts
      s.setSelMode(SelMode.vertex);
      s.subdivideSelected();
      expect(s.editObj!.mesh.vertices.length, 20);
    });

    test('fill creates a face and switches to face mode', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.vertex);
      s.selVerts = {0, 1, 2, 3};
      s.fillFaces();
      expect(s.selMode, SelMode.face);
      expect(s.editObj!.mesh.faces.length, 7);
    });

    test('fill needs 3 verts', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.vertex);
      s.selVerts = {0, 1};
      s.fillFaces();
      expect(s.statusHint, contains('3+'));
    });

    test('mergeByDistance', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.vertex);
      s.editObj!.mesh.vertices[0] = Vec3.zero;
      s.editObj!.mesh.vertices[7] = const Vec3(0.0001, 0, 0);
      s.selVerts = {0, 7};
      s.mergeByDistance();
      expect(s.editObj!.mesh.vertices.length, 7);
    });

    test('mergeByDistance needs 2 verts', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.vertex);
      s.selVerts = {0};
      s.mergeByDistance();
      expect(s.statusHint, contains('2+'));
    });

    test('flipNormals flips selected faces', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.face);
      s.selFaces = {1};
      s.flipNormals();
      expect(s.editObj!.mesh.faceNormal(1).z, -1);
    });

    test('delete faces', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.face);
      s.selFaces = {0, 1};
      s.deleteSelected();
      expect(s.editObj!.mesh.faces.length, 4);
    });

    test('delete edges', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.edge);
      s.selEdges = {0};
      s.deleteSelected();
      expect(s.editObj!.mesh.faces.length, 4);
    });

    test('delete vertices', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.vertex);
      s.selVerts = {0};
      s.deleteSelected();
      expect(s.editObj!.mesh.vertices.length, 7);
    });
  });

  group('transforms', () {
    test('grab translates object', () {
      final s = state();
      s.beginTransform(TransformKind.grab, const Offset(400, 300), viewportHeight: 600);
      s.updateTransform(const Offset(500, 300));
      s.confirmTransform();
      expect(s.scene.objects[0].location.x, isNot(0));
      expect(s.dirty, isTrue);
    });

    test('grab with axis constraint only moves that axis', () {
      final s = state();
      s.beginTransform(TransformKind.grab, const Offset(400, 300), viewportHeight: 600);
      s.constrainAxis(0);
      s.updateTransform(const Offset(500, 320));
      s.confirmTransform();
      final l = s.scene.objects[0].location;
      expect(l.x, isNot(0));
      expect(l.y, 0);
      expect(l.z, 0);
    });

    test('constrainAxis toggles off on repeat', () {
      final s = state();
      s.beginTransform(TransformKind.grab, const Offset(400, 300), viewportHeight: 600);
      s.constrainAxis(1);
      s.constrainAxis(1);
      expect(s.transform!.axis, -1);
      s.cancelTransform();
    });

    test('rotate changes object rotation', () {
      final s = state();
      s.beginTransform(TransformKind.rotate, const Offset(400, 300), viewportHeight: 600);
      s.updateTransform(const Offset(500, 300));
      s.confirmTransform();
      final r = s.scene.objects[0].rotation;
      expect(r.length, greaterThan(0));
    });

    test('scale changes object scale', () {
      final s = state();
      s.beginTransform(TransformKind.scale, const Offset(400, 300), viewportHeight: 600);
      s.updateTransform(const Offset(500, 300));
      s.confirmTransform();
      expect(s.scene.objects[0].scale.x, greaterThan(1));
    });

    test('scale with axis lock', () {
      final s = state();
      s.beginTransform(TransformKind.scale, const Offset(400, 300), viewportHeight: 600);
      s.constrainAxis(2);
      s.updateTransform(const Offset(500, 300));
      s.confirmTransform();
      expect(s.scene.objects[0].scale.z, greaterThan(1));
      expect(s.scene.objects[0].scale.x, 1);
    });

    test('cancel restores original transform', () {
      final s = state();
      s.beginTransform(TransformKind.grab, const Offset(400, 300), viewportHeight: 600);
      s.updateTransform(const Offset(500, 320));
      s.cancelTransform();
      expect(s.scene.objects[0].location, Vec3.zero);
      expect(s.transform, isNull);
    });

    test('first move sets start pointer (extrude path)', () {
      final s = state();
      s.beginTransform(TransformKind.grab, null, viewportHeight: 600);
      s.updateTransform(const Offset(400, 300)); // sets start, no delta
      expect(s.scene.objects[0].location, Vec3.zero);
      s.updateTransform(const Offset(450, 300));
      expect(s.scene.objects[0].location.x, isNot(0));
      s.cancelTransform();
    });

    test('snap rounds translation to grid', () {
      final s = state();
      s.snapEnabled = true;
      s.gridSize = 1.0;
      s.beginTransform(TransformKind.grab, const Offset(400, 300), viewportHeight: 600);
      s.updateTransform(const Offset(410, 302));
      s.confirmTransform();
      final l = s.scene.objects[0].location;
      for (final c in [l.x, l.y, l.z]) {
        expect(c - c.roundToDouble(), 0);
      }
    });

    test('snap rounds rotation to 5 degrees', () {
      final s = state();
      s.snapEnabled = true;
      s.beginTransform(TransformKind.rotate, const Offset(400, 300), viewportHeight: 600);
      s.updateTransform(const Offset(420, 300));
      final deg = s.transform!.rotAngle * 180 / 3.14159265;
      expect(deg % 5, closeTo(0, 1e-6));
      s.cancelTransform();
    });

    test('snap rounds scale', () {
      final s = state();
      s.snapEnabled = true;
      s.beginTransform(TransformKind.scale, const Offset(400, 300), viewportHeight: 600);
      s.updateTransform(const Offset(430, 300));
      final f = s.transform!.scaleFactor.x;
      expect(f * 10 - (f * 10).roundToDouble(), closeTo(0, 1e-9));
      s.cancelTransform();
    });

    test('edit mode grab moves selected verts', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.vertex);
      s.selVerts = {0};
      final before = s.editObj!.mesh.vertices[0];
      s.beginTransform(TransformKind.grab, const Offset(400, 300), viewportHeight: 600);
      s.updateTransform(const Offset(430, 300));
      s.confirmTransform();
      expect(s.editObj!.mesh.vertices[0].distanceTo(before), greaterThan(0));
      expect(s.editObj!.mesh.vertices[1], const Vec3(1, -1, -1)); // unselected vert untouched
    });

    test('edit mode rotate and scale verts', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.vertex);
      s.selVerts = {0, 1}; // two verts so the pivot isn't a point
      final before = s.editObj!.mesh.vertices[0];
      s.beginTransform(TransformKind.rotate, const Offset(400, 300), viewportHeight: 600);
      s.updateTransform(const Offset(450, 300));
      s.confirmTransform();
      expect(s.editObj!.mesh.vertices[0].distanceTo(before), greaterThan(0));
      s.beginTransform(TransformKind.scale, const Offset(400, 300), viewportHeight: 600);
      s.updateTransform(const Offset(430, 300));
      s.confirmTransform();
    });

    test('beginTransform with nothing selected warns', () {
      final s = state();
      s.deselectAll();
      s.beginTransform(TransformKind.grab, const Offset(400, 300));
      expect(s.transform, isNull);
      expect(s.statusHint, 'Nothing selected');
      s.enterEditMode();
      s.deselectAll();
      s.selVerts = {};
      s.beginTransform(TransformKind.grab, const Offset(400, 300));
      expect(s.transform, isNull);
    });

    test('confirmTransform without session is a no-op', () {
      final s = state();
      s.confirmTransform();
      s.cancelTransform();
      expect(s.transform, isNull);
    });

    test('transform label text', () {
      final s = state();
      s.beginTransform(TransformKind.grab, const Offset(400, 300), viewportHeight: 600);
      s.updateTransform(const Offset(410, 295));
      expect(s.transform!.label, contains('Move'));
      s.constrainAxis(0);
      expect(s.transform!.label, contains('X'));
      s.cancelTransform();
      s.beginTransform(TransformKind.rotate, const Offset(400, 300), viewportHeight: 600);
      s.updateTransform(const Offset(410, 300));
      expect(s.transform!.label, contains('Rotate'));
      s.cancelTransform();
      s.beginTransform(TransformKind.scale, const Offset(400, 300), viewportHeight: 600);
      s.updateTransform(const Offset(410, 300));
      expect(s.transform!.label, contains('Scale'));
      s.cancelTransform();
    });
  });

  group('undo', () {
    test('undo/redo restores scene', () {
      final s = state();
      final n = s.scene.objects.length;
      s.addPrimitive('Plane');
      expect(s.scene.objects.length, n + 1);
      s.undo();
      expect(s.scene.objects.length, n);
      s.redo();
      expect(s.scene.objects.length, n + 1);
    });

    test('undo with empty stack is safe', () {
      final s = state();
      while (s.undoStack.canUndo) {
        s.undo();
      }
      s.undo(); // no crash
      s.redo(); // empty redo safe after drain
    });

    test('undo restores edit-mode state', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.face);
      s.selFaces = {1};
      s.inset(0.3);
      final faces = s.editObj!.mesh.faces.length;
      s.undo();
      expect(s.editObj!.mesh.faces.length, lessThan(faces));
    });
  });

  group('properties', () {
    test('name/loc/rot/scale setters', () {
      final s = state();
      s.setActiveName('Boxy');
      expect(s.activeObj!.name, 'Boxy');
      s.setActiveLocation(const Vec3(1, 2, 3));
      expect(s.activeObj!.location, const Vec3(1, 2, 3));
      s.setActiveRotation(const Vec3(0.1, 0, 0));
      expect(s.activeObj!.rotation.x, 0.1);
      s.setActiveScale(const Vec3(2, 2, 2));
      expect(s.activeObj!.scale.x, 2);
      s.setActiveName('');
      expect(s.activeObj!.name, 'Boxy');
    });

    test('setters without selection are no-ops', () {
      final s = state(cube: false);
      s.setActiveName('x');
      s.setActiveLocation(Vec3.unitX);
      s.setActiveRotation(Vec3.unitX);
      s.setActiveScale(Vec3.unitX);
      s.setActiveColor(const Color(0xFF000000));
      s.setActiveMetallic(1);
      s.setActiveRoughness(1);
      s.toggleSmoothShading();
      s.addModifier('mirror');
      expect(s.scene.objects, isEmpty);
    });

    test('material setters', () {
      final s = state();
      s.setActiveColor(const Color(0xFFFF0000));
      expect(s.activeObj!.material.color, const Color(0xFFFF0000));
      s.setActiveMetallic(0.7);
      s.setActiveRoughness(0.2);
      expect(s.activeObj!.material.metallic, 0.7);
      expect(s.activeObj!.material.roughness, 0.2);
    });

    test('setObjectVisible', () {
      final s = state();
      s.setObjectVisible(0, false);
      expect(s.scene.objects[0].visible, isFalse);
      s.setObjectVisible(99, true); // out of range, safe
      s.setObjectVisible(0, true);
      expect(s.scene.objects[0].visible, isTrue);
    });

    test('toggleSmoothShading object and edit', () {
      final s = state();
      s.toggleSmoothShading();
      expect(s.scene.objects[0].smoothShading, isTrue);
      s.enterEditMode();
      s.toggleSmoothShading();
      expect(s.editObj!.smoothShading, isFalse);
    });
  });

  group('modifiers', () {
    test('add each type', () {
      final s = state();
      for (final t in ['mirror', 'array', 'subdivision', 'bevel', 'solidify']) {
        s.addModifier(t);
      }
      expect(s.activeObj!.modifiers.length, 5);
      expect(s.activeObj!.evaluatedMesh.vertices.length, greaterThan(8));
      expect(() => s.addModifier('bogus'), throwsArgumentError);
    });

    test('remove / move / apply', () {
      final s = state();
      s.addModifier('array');
      s.addModifier('mirror');
      // move mirror above array
      s.moveModifier(0, 1, -1);
      expect(s.activeObj!.modifiers.first.type, 'mirror');
      s.moveModifier(0, 0, -1); // at top, no-op
      s.moveModifier(0, 0, 99); // out of range, no-op
      // apply the top (mirror) — baked, array stays live
      s.applyModifier(0, 0);
      expect(s.activeObj!.modifiers.length, 1);
      expect(s.activeObj!.modifiers.single.type, 'array');
      expect(s.activeObj!.mesh.vertices.length, 16); // mirror baked in
      s.removeModifier(0, 0);
      expect(s.activeObj!.modifiers, isEmpty);
      // bounds checking
      s.removeModifier(99, 0);
      s.moveModifier(0, 0, 1);
      s.applyModifier(0, 0);
      s.applyAllModifiers(99);
      s.applyAllModifiers(0); // empty stack no-op
    });

    test('applyAllModifiers bakes the stack', () {
      final s = state();
      s.addModifier('subdivision');
      s.applyAllModifiers(0);
      expect(s.activeObj!.modifiers, isEmpty);
      expect(s.activeObj!.mesh.faces.length, 24);
    });
  });

  group('view', () {
    test('presets and perspective toggle', () {
      final s = state();
      s.setViewPreset('top');
      expect(s.camera.pitch, greaterThan(1.0));
      s.togglePerspective();
      expect(s.camera.perspective, isFalse);
    });

    test('frameSelected in object mode', () {
      final s = state();
      s.frameSelected(1.5);
      expect(s.camera.distance, isNot(10));
    });

    test('frameSelected with empty selection frames all', () {
      final s = state();
      s.deselectAll();
      s.frameSelected(1.5);
      expect(s.camera.distance, isNot(10));
    });

    test('frameSelected empty scene no-op', () {
      final s = state(cube: false);
      s.deselectAll();
      s.frameSelected(1.5);
      expect(s.camera.distance, 10);
    });

    test('frameSelected edit mode', () {
      final s = state();
      s.enterEditMode();
      s.setSelMode(SelMode.vertex);
      s.selVerts = {0};
      s.frameSelected(1.5);
      expect(s.camera.target.distanceTo(Vec3.zero), greaterThan(0));
    });

    test('frameSelected edit mode with empty selection is no-op', () {
      final s = state();
      s.enterEditMode();
      s.deselectAll();
      final d = s.camera.distance;
      s.frameSelected(1.5);
      expect(s.camera.distance, d);
    });

    test('shading cycle and snap', () {
      final s = state();
      s.cycleShading();
      expect(s.shading, ShadingMode.materialPreview);
      s.cycleShading();
      s.cycleShading();
      expect(s.shading, ShadingMode.solid);
      s.setShading(ShadingMode.wireframe);
      expect(s.shading, ShadingMode.wireframe);
      s.toggleSnap();
      expect(s.snapEnabled, isTrue);
      s.toggleOverlays();
      expect(s.showOverlays, isFalse);
    });

    test('setTool', () {
      final s = state();
      s.setTool(Tool.move);
      expect(s.tool, Tool.move);
    });
  });

  group('persistence', () {
    test('save/load text roundtrip', () {
      final s = state();
      s.setActiveName('Roundtrip');
      final text = s.saveSceneText();
      s.newScene();
      expect(s.scene.objects, isEmpty);
      s.loadSceneText(text);
      expect(s.scene.objects.single.name, 'Roundtrip');
      expect(s.mode, EditorMode.object);
    });

    test('exportObj and importObj', () {
      final s = state();
      final obj = s.exportObj();
      expect(obj, contains('o Cube'));
      s.newScene();
      s.importObj(obj);
      expect(s.scene.objects.single.name, 'Imported');
      expect(s.scene.objects.single.mesh.vertices.length, 8);
    });

    test('importObj with garbage hints', () {
      final s = state(cube: false);
      s.importObj('not an obj');
      expect(s.statusHint, 'No geometry found');
    });
  });
}
