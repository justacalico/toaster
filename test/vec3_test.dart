import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:toaster/core/vec3.dart';

void main() {
  group('Vec3', () {
    test('arithmetic', () {
      const a = Vec3(1, 2, 3);
      const b = Vec3(4, 5, 6);
      expect(a + b, const Vec3(5, 7, 9));
      expect(a - b, const Vec3(-3, -3, -3));
      expect(-a, const Vec3(-1, -2, -3));
      expect(a * 2, const Vec3(2, 4, 6));
      expect(a / 2, const Vec3(0.5, 1, 1.5));
      expect(a.dot(b), 32);
      expect(a.cross(b), const Vec3(-3, 6, -3));
      expect(Vec3.zero.length, 0);
      expect(const Vec3(3, 4, 0).length, 5);
      expect(a.length2, 14);
    });

    test('normalize and distance', () {
      expect(const Vec3(0, 0, 5).normalized(), Vec3.unitZ);
      expect(Vec3.zero.normalized(), Vec3.zero);
      expect(const Vec3(0, 0, 0).distanceTo(const Vec3(3, 4, 0)), 5);
      expect(const Vec3(0, 0, 0).lerp(const Vec3(2, 0, 0), 0.25), const Vec3(0.5, 0, 0));
    });

    test('min/max/mulVec/withAxis/axisValue', () {
      const a = Vec3(1, 5, 3);
      const b = Vec3(4, 2, 6);
      expect(a.min(b), const Vec3(1, 2, 3));
      expect(a.max(b), const Vec3(4, 5, 6));
      expect(a.mulVec(b), const Vec3(4, 10, 18));
      expect(a.withAxis(0, 9), const Vec3(9, 5, 3));
      expect(a.withAxis(1, 9), const Vec3(1, 9, 3));
      expect(a.withAxis(2, 9), const Vec3(1, 5, 9));
      expect(a.axisValue(0), 1);
      expect(a.axisValue(1), 5);
      expect(a.axisValue(2), 3);
    });

    test('json roundtrip and equality', () {
      const v = Vec3(1.5, -2, 3.25);
      expect(Vec3.fromJson(v.toJson()), v);
      expect(v.hashCode, const Vec3(1.5, -2, 3.25).hashCode);
      expect(v.toString(), contains('Vec3('));
    });
  });

  group('Mat4', () {
    test('identity leaves points unchanged', () {
      const p = Vec3(1, 2, 3);
      expect(Mat4.identity().transformPoint(p), p);
      expect(Mat4.identity().transformDir(p), p);
    });

    test('translation and scaling', () {
      const p = Vec3(1, 1, 1);
      expect(Mat4.translation(const Vec3(1, 2, 3)).transformPoint(p), const Vec3(2, 3, 4));
      expect(Mat4.scaling(const Vec3(2, 3, 4)).transformPoint(p), const Vec3(2, 3, 4));
      expect(Mat4.translation(const Vec3(5, 0, 0)).transformDir(p), p);
    });

    test('rotations', () {
      const p = Vec3(1, 0, 0);
      final rz = Mat4.rotationZ(math.pi / 2).transformPoint(p);
      expect(rz.x, closeTo(0, 1e-9));
      expect(rz.y, closeTo(1, 1e-9));
      final rx = Mat4.rotationX(math.pi / 2).transformPoint(Vec3.unitY);
      expect(rx.z, closeTo(1, 1e-9));
      final ry = Mat4.rotationY(math.pi / 2).transformPoint(Vec3.unitZ);
      expect(ry.x, closeTo(1, 1e-9));
      final ra = Mat4.rotationAxis(Vec3.unitZ, math.pi / 2).transformPoint(p);
      expect(ra.y, closeTo(1, 1e-9));
    });

    test('multiplication order', () {
      // T * S applied to point scales first, then translates
      final m = Mat4.translation(const Vec3(10, 0, 0)) * Mat4.scaling(const Vec3(2, 2, 2));
      expect(m.transformPoint(const Vec3(1, 0, 0)), const Vec3(12, 0, 0));
    });

    test('inverse roundtrip', () {
      final m = Mat4.translation(const Vec3(3, -2, 7)) *
          Mat4.rotationZ(0.7) *
          Mat4.rotationY(0.3) *
          Mat4.scaling(const Vec3(2, 1.5, 0.5));
      final inv = m.inverted()!;
      final p = m.transformPoint(const Vec3(1.5, -2.5, 0.75));
      final back = inv.transformPoint(p);
      expect(back.x, closeTo(1.5, 1e-8));
      expect(back.y, closeTo(-2.5, 1e-8));
      expect(back.z, closeTo(0.75, 1e-8));
    });

    test('singular matrix has no inverse', () {
      expect(Mat4.scaling(Vec3.zero).inverted(), isNull);
    });

    test('lookAt frames the target', () {
      final v = Mat4.lookAt(const Vec3(0, 0, 10), Vec3.zero, Vec3.unitZ);
      final origin = v.transformPoint(Vec3.zero);
      expect(origin.z, closeTo(-10, 1e-9)); // in front of camera
      // degenerate up vector falls back
      final v2 = Mat4.lookAt(const Vec3(0, 0, 10), Vec3.zero, Vec3.unitY);
      expect(v2.transformPoint(Vec3.zero).z, closeTo(-10, 1e-9));
    });

    test('perspective divides by w', () {
      final p = Mat4.perspective(math.pi / 3, 1, 0.1, 100);
      final c = p.transformRaw(const Vec3(0, 0, -5));
      expect(c[3], closeTo(5, 1e-9));
      final pt = p.transformPoint(const Vec3(0, 0, -5));
      expect(pt.x, closeTo(0, 1e-9));
      expect(pt.y, closeTo(0, 1e-9));
    });

    test('ortho maps height linearly', () {
      final p = Mat4.ortho(10, 1, 0.1, 100);
      final a = p.transformPoint(const Vec3(0, 0, -10));
      final b = p.transformPoint(const Vec3(0, 0, -50));
      expect(a.x, closeTo(b.x, 1e-9)); // no perspective divide
    });

    test('transposed', () {
      final m = Mat4.identity();
      m.m[1] = 5;
      expect(m.transposed().m[4], 5);
    });
  });
}
