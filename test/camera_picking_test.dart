import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:toaster/core/camera.dart';
import 'package:toaster/core/picking.dart';
import 'package:toaster/core/primitives.dart';
import 'package:toaster/core/scene.dart';
import 'package:toaster/core/vec3.dart';

void main() {
  group('OrbitCamera', () {
    test('eye orbits the target', () {
      final c = OrbitCamera(distance: 10, yaw: 0, pitch: 0);
      expect(c.eye, const Vec3(10, 0, 0));
      final c2 = OrbitCamera(distance: 10, yaw: math.pi / 2, pitch: 0);
      expect(c2.eye.y, closeTo(10, 1e-9));
    });

    test('orbit clamps pitch', () {
      final c = OrbitCamera();
      c.orbit(0, 100);
      expect(c.pitch, lessThan(math.pi / 2));
      c.orbit(0, -200);
      expect(c.pitch, greaterThan(-math.pi / 2));
      c.orbit(1.0, 0);
      expect(c.yaw, isNot(0));
    });

    test('pan moves target perpendicular to view', () {
      final c = OrbitCamera();
      final before = c.target;
      c.pan(100, 0, 600);
      expect(c.target.distanceTo(before), greaterThan(0));
    });

    test('zoom clamps both modes', () {
      final c = OrbitCamera();
      c.zoom(1e9);
      expect(c.distance, 500);
      c.zoom(1e-9);
      expect(c.distance, 0.1);
      c.togglePerspective();
      c.zoom(1e9);
      expect(c.orthoHeight, 500);
      c.zoom(1e-9);
      expect(c.orthoHeight, 0.05);
    });

    test('project returns null behind camera', () {
      final c = OrbitCamera();
      final behind = c.eye + c.forward * -5;
      expect(c.project(behind, 800, 600), isNull);
    });

    test('project puts target at screen center', () {
      final c = OrbitCamera();
      final p = c.project(c.target, 800, 600)!;
      expect(p.$1, closeTo(400, 0.5));
      expect(p.$2, closeTo(300, 0.5));
      expect(p.$3, closeTo(10, 0.5));
    });

    test('ortho projection', () {
      final c = OrbitCamera()..togglePerspective();
      final p = c.project(c.target, 800, 600)!;
      expect(p.$1, closeTo(400, 0.5));
    });

    test('ray through center hits forward axis', () {
      final c = OrbitCamera();
      final (ro, rd) = c.ray(400, 300, 800, 600);
      expect(ro, c.eye);
      expect(rd.distanceTo(c.forward), lessThan(1e-9));
    });

    test('ortho ray is parallel to forward', () {
      final c = OrbitCamera()..togglePerspective();
      final (_, rd) = c.ray(100, 100, 800, 600);
      expect(rd.distanceTo(c.forward), lessThan(1e-9));
    });

    test('screenDeltaToWorld scales with distance', () {
      final c = OrbitCamera();
      final near = c.screenDeltaToWorld(10, 0, 600, 5);
      final far = c.screenDeltaToWorld(10, 0, 600, 50);
      expect(far.length, greaterThan(near.length * 5));
      final ortho = OrbitCamera()..togglePerspective();
      final d = ortho.screenDeltaToWorld(10, 0, 600, 50);
      expect(d.length, greaterThan(0));
    });

    test('view presets', () {
      final c = OrbitCamera();
      c.setView('front');
      expect(c.yaw, -math.pi / 2);
      c.setView('back');
      expect(c.yaw, math.pi / 2);
      c.setView('right');
      expect(c.yaw, 0);
      c.setView('left');
      expect(c.yaw, math.pi);
      c.setView('top');
      expect(c.pitch, closeTo(math.pi / 2, 0.01));
      c.setView('bottom');
      expect(c.pitch, closeTo(-math.pi / 2, 0.01));
      c.setView('other');
      expect(c.distance, 10);
    });

    test('frame fits bounds', () {
      final c = OrbitCamera();
      c.frame(const Vec3(-5, -5, -5), const Vec3(5, 5, 5), 1.5);
      expect(c.target, Vec3.zero);
      expect(c.distance, greaterThan(5));
      c.frame(Vec3.zero, Vec3.zero, 1.5);
      expect(c.distance, 3);
    });

    test('clone is independent', () {
      final c = OrbitCamera();
      final d = c.clone();
      d.distance = 99;
      expect(c.distance, 10);
    });
  });

  group('picking', () {
    test('rayTriangle hit and miss', () {
      const a = Vec3(-1, -1, 0), b = Vec3(1, -1, 0), c = Vec3(0, 1, 0);
      const ro = Vec3(0, 0, 5);
      const rd = Vec3(0, 0, -1);
      expect(rayTriangle(ro, rd, a, b, c), closeTo(5, 1e-9));
      // miss: ray pointing away from the triangle
      expect(rayTriangle(ro, const Vec3(0, 0, 1), a, b, c), isNull);
      // parallel ray
      expect(rayTriangle(ro, const Vec3(1, 0, 0), a, b, c), isNull);
      // edge cases: u/v outside
      expect(rayTriangle(const Vec3(5, 5, 5), rd, a, b, c), isNull);
    });

    test('rayMesh finds closest face', () {
      final obj = SceneObject(name: 'c', mesh: Primitives.cube());
      const ro = Vec3(0, 0, 10);
      const rd = Vec3(0, 0, -1);
      final hit = rayMesh(ro, rd, obj)!;
      expect(hit.$1, closeTo(9, 1e-6));
      expect(hit.$2, greaterThanOrEqualTo(0));
    });

    test('rayMesh misses', () {
      final obj = SceneObject(name: 'c', mesh: Primitives.cube());
      expect(rayMesh(const Vec3(0, 0, 10), Vec3.unitX, obj), isNull);
    });

    test('pickObject respects visibility and filter', () {
      final scene = Scene(objects: [
        SceneObject(name: 'a', mesh: Primitives.cube()),
        SceneObject(name: 'b', mesh: Primitives.cube(), location: const Vec3(0, 0, -5)),
      ]);
      const ro = Vec3(0, 0, 10);
      const rd = Vec3(0, 0, -1);
      expect(pickObject(ro, rd, scene)!.$1, 0);
      scene.objects[0].visible = false;
      expect(pickObject(ro, rd, scene)!.$1, 1);
      expect(pickObject(ro, rd, scene, filter: (i) => i == 0), isNull);
      expect(pickObject(const Vec3(0, 0, 10), Vec3.unitY, scene), isNull);
    });

    test('pointSegmentDist', () {
      expect(pointSegmentDist(5, 5, 0, 0, 10, 0), 25);
      expect(pointSegmentDist(-5, 0, 0, 0, 10, 0), 25);
      expect(pointSegmentDist(0, 0, 0, 0, 0, 0), 0);
    });
  });
}
