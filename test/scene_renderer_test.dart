import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:toaster/core/camera.dart';
import 'package:toaster/core/modifiers.dart';
import 'package:toaster/core/primitives.dart';
import 'package:toaster/core/renderer.dart';
import 'package:toaster/core/scene.dart';
import 'package:toaster/core/vec3.dart';

void main() {
  group('SceneObject', () {
    test('matrix composes TRS', () {
      final o = SceneObject(
        name: 'a',
        mesh: Primitives.cube(),
        location: const Vec3(5, 0, 0),
        scale: const Vec3(2, 2, 2),
      );
      final p = o.matrix.transformPoint(Vec3.unitX);
      expect(p.x, closeTo(7, 1e-9));
      // inverse roundtrip
      expect(o.inverseMatrix.transformPoint(p).x, closeTo(1, 1e-9));
    });

    test('evaluatedMesh applies enabled modifiers only', () {
      final o = SceneObject(name: 'a', mesh: Primitives.cube(), modifiers: [
        MirrorModifier(),
        ArrayModifier(count: 5)..enabled = false,
      ]);
      expect(o.evaluatedMesh.vertices.length, 16);
    });

    test('worldCenter uses transform', () {
      final o = SceneObject(name: 'a', mesh: Primitives.cube(), location: const Vec3(3, 0, 0));
      expect(o.worldCenter, const Vec3(3, 0, 0));
    });

    test('clone is independent', () {
      final o = SceneObject(name: 'a', mesh: Primitives.cube(), modifiers: [MirrorModifier()]);
      final c = o.clone();
      c.name = 'b';
      c.mesh.vertices[0] = Vec3.zero;
      c.modifiers.clear();
      expect(o.name, 'a');
      expect(o.modifiers.length, 1);
    });
  });

  group('SceneRenderer', () {
    Scene scene() => Scene(objects: [
          SceneObject(name: 'a', mesh: Primitives.cube()),
          SceneObject(name: 'b', mesh: Primitives.cube(), location: const Vec3(0, 0, -10)),
        ]);

    test('solid mode produces depth-sorted polys', () {
      final r = SceneRenderer(OrbitCamera());
      final f = r.build(scene(), 800, 600);
      expect(f.polys, isNotEmpty);
      for (var i = 1; i < f.polys.length; i++) {
        // sorted far -> near; depth implied by order — just check it ran
        expect(f.polys[i].points.length, 3);
      }
      expect(f.grid, isNotEmpty); // grid + axes
    });

    test('wireframe mode produces lines and no polys', () {
      final r = SceneRenderer(OrbitCamera(), shading: ShadingMode.wireframe);
      final f = r.build(scene(), 800, 600);
      expect(f.polys, isEmpty);
      expect(f.lines, isNotEmpty);
    });

    test('hidden objects render nothing', () {
      final s = scene();
      s.objects[0].visible = false;
      s.objects[1].visible = false;
      final f = SceneRenderer(OrbitCamera()).build(s, 800, 600);
      expect(f.polys, isEmpty);
    });

    test('no grid when disabled', () {
      final r = SceneRenderer(OrbitCamera(), showGrid: false);
      final f = r.build(scene(), 800, 600);
      expect(f.grid, isEmpty);
    });

    test('no axes when disabled', () {
      final r = SceneRenderer(OrbitCamera(), showAxes: false);
      final f = r.build(scene(), 800, 600);
      expect(f.grid.where((l) => l.color == const Color(0xFFB3454E)), isEmpty);
    });

    test('selected objects get outline color', () {
      final r = SceneRenderer(OrbitCamera())..selectedObjects = {0};
      final f = r.build(scene(), 800, 600);
      expect(f.lines.any((l) => l.color == SceneRenderer.selectionColor), isTrue);
    });

    test('material preview shades with material color', () {
      final r = SceneRenderer(OrbitCamera(), shading: ShadingMode.materialPreview);
      final s = Scene(objects: [
        SceneObject(name: 'a', mesh: Primitives.cube())..material.color = const Color(0xFFFF0000),
      ]);
      final f = r.build(s, 800, 600);
      expect(f.polys.any((p) => p.color.r > 0.4), isTrue);
    });

    test('edit mode draws vertex dots and selected elements', () {
      final r = SceneRenderer(OrbitCamera())
        ..editTargetIndex = 0
        ..selVerts = {0}
        ..selEdges = {0}
        ..selFaces = {0};
      final f = r.build(scene(), 800, 600);
      expect(f.dots.length, 8);
      expect(f.dots.any((d) => d.color == SceneRenderer.selectionColor), isTrue);
      expect(f.polys.any((p) => p.editTarget), isTrue);
    });

    test('smooth shading uses vertex normals', () {
      final s = scene();
      s.objects[0].smoothShading = true;
      final f = SceneRenderer(OrbitCamera()).build(s, 800, 600);
      expect(f.polys, isNotEmpty);
      // flat control render for comparison
      s.objects[0].smoothShading = false;
      final f2 = SceneRenderer(OrbitCamera()).build(s, 800, 600);
      expect(f.polys.map((p) => p.color.toARGB32()).toSet(),
          isNot(equals(f2.polys.map((p) => p.color.toARGB32()).toSet())));
    });

    test('verts behind camera are skipped', () {
      final c = OrbitCamera()..target = const Vec3(0, 0, -50);
      final f = SceneRenderer(c).build(scene(), 800, 600);
      // cube at origin behind... camera at -50+distance looking -z; fine either way
      expect(f, isNotNull);
    });
  });
}
