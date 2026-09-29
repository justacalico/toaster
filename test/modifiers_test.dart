import 'package:flutter_test/flutter_test.dart';
import 'package:toaster/core/modifiers.dart';
import 'package:toaster/core/primitives.dart';
import 'package:toaster/core/vec3.dart';

void main() {
  group('MirrorModifier', () {
    test('doubles geometry across X', () {
      final cube = Primitives.cube();
      final m = MirrorModifier(axis: 0, merge: false).apply(cube);
      expect(m.vertices.length, 16);
      expect(m.faces.length, 12);
      // mirrored verts have negated x
      for (var i = 8; i < 16; i++) {
        expect(m.vertices[i].x, -cube.vertices[i - 8].x);
      }
    });

    test('merge welds on-plane verts', () {
      // cube shifted +1 in x: its -x face sits on the mirror plane
      final cube = Primitives.cube()..transform(Mat4.translation(const Vec3(1, 0, 0)));
      final m = MirrorModifier(axis: 0, merge: true, mergeDistance: 0.01).apply(cube);
      // 8 orig + 4 mirrored (only the x=2 verts mirror; x=0 verts weld on-plane)
      expect(m.vertices.length, 12);
      // the on-plane face is not duplicated
      expect(m.faces.length, 11);
      final (lo, hi) = m.bounds;
      expect(lo.x, -2); // mirrored side
      expect(hi.x, 2); // original side
    });

    test('on-plane faces are not duplicated', () {
      final plane = Primitives.plane(); // z=0, on the Z plane
      final m = MirrorModifier(axis: 2, merge: true).apply(plane);
      expect(m.faces.length, 1);
    });

    test('roundtrip json', () {
      final m = MirrorModifier(axis: 1, merge: false, mergeDistance: 0.5)..enabled = false;
      final r = MeshModifier.fromJson(m.toJson()) as MirrorModifier;
      expect(r.axis, 1);
      expect(r.merge, isFalse);
      expect(r.mergeDistance, 0.5);
      expect(r.enabled, isFalse);
      expect(r.clone().axis, 1);
    });
  });

  group('ArrayModifier', () {
    test('repeats mesh with relative offset', () {
      final m = ArrayModifier(count: 3).apply(Primitives.cube(size: 2));
      expect(m.vertices.length, 24);
      expect(m.faces.length, 18);
      // cube 2 shifted by its own width (2) in x
      expect(m.vertices[8].x, 1); // copy 1 vert0 x = -1 + 2
    });

    test('constant offset', () {
      final m = ArrayModifier(
        count: 2,
        useRelativeOffset: false,
        constantOffset: const Vec3(0, 0, 5),
      ).apply(Primitives.cube());
      expect(m.bounds.$2.z, 6);
    });

    test('count<=1 is identity', () {
      final m = ArrayModifier(count: 1).apply(Primitives.cube());
      expect(m.vertices.length, 8);
    });

    test('roundtrip json', () {
      final m = ArrayModifier(
        count: 4,
        constantOffset: const Vec3(1, 2, 3),
        useRelativeOffset: false,
        relativeOffset: const Vec3(0, 1, 0),
      );
      final r = MeshModifier.fromJson(m.toJson()) as ArrayModifier;
      expect(r.count, 4);
      expect(r.constantOffset, const Vec3(1, 2, 3));
      expect(r.useRelativeOffset, isFalse);
      expect(r.clone().count, 4);
    });
  });

  group('SubdivisionModifier', () {
    test('cube level 1 gives 24 quads', () {
      final m = SubdivisionModifier(levels: 1).apply(Primitives.cube());
      expect(m.faces.length, 24);
      for (final f in m.faces) {
        expect(f.length, 4);
      }
    });

    test('shrinks the cube toward a sphere', () {
      final m = SubdivisionModifier(levels: 2).apply(Primitives.cube());
      final (_, hi) = m.bounds;
      expect(hi.x, lessThan(1.0)); // corners pull in
      expect(hi.x, greaterThan(0.5));
    });

    test('handles open surfaces (plane)', () {
      final m = SubdivisionModifier(levels: 1).apply(Primitives.plane());
      expect(m.faces.length, 4);
    });

    test('subdivides loose edges', () {
      final wire = Primitives.cube();
      wire.faces.clear();
      wire.edges.add((0, 1));
      final m = SubdivisionModifier(levels: 1).apply(wire);
      expect(m.edges.length, 2);
    });

    test('levels 0 is identity', () {
      final m = SubdivisionModifier(levels: 0).apply(Primitives.cube());
      expect(m.faces.length, 6);
    });

    test('roundtrip json', () {
      final r = MeshModifier.fromJson(SubdivisionModifier(levels: 2).toJson());
      expect((r as SubdivisionModifier).levels, 2);
      expect(r.clone().type, 'subdivision');
    });
  });

  group('BevelModifier', () {
    test('cube bevel adds chamfer and cap faces', () {
      final m = BevelModifier(amount: 0.2).apply(Primitives.cube());
      // 6 shrunk faces + 12 edge quads + 8 vertex caps = 26
      expect(m.faces.length, 26);
      // 2 corners per original face corner: 6 faces * 4 corners * 2 = 48
      expect(m.vertices.length, 48);
    });

    test('amount 0 is identity', () {
      final m = BevelModifier(amount: 0).apply(Primitives.cube());
      expect(m.faces.length, 6);
    });

    test('empty mesh stays empty', () {
      final m = BevelModifier().apply(Primitives.cube()..faces.clear());
      expect(m.faces, isEmpty);
    });

    test('open mesh produces boundary chamfer', () {
      final m = BevelModifier(amount: 0.2).apply(Primitives.plane());
      expect(m.faces.length, greaterThan(1));
    });

    test('roundtrip json', () {
      final r = MeshModifier.fromJson(BevelModifier(amount: 0.3, segments: 2).toJson()) as BevelModifier;
      expect(r.amount, 0.3);
      expect(r.segments, 2);
      expect(r.clone().amount, 0.3);
    });
  });

  group('SolidifyModifier', () {
    test('plane becomes a box', () {
      final m = SolidifyModifier(thickness: 0.1).apply(Primitives.plane());
      expect(m.faces.length, 2 + 4); // front + back + 4 walls
      expect(m.vertices.length, 8);
    });

    test('closed mesh gets double skin', () {
      final m = SolidifyModifier().apply(Primitives.cube());
      expect(m.faces.length, 12);
    });

    test('preserves loose edges', () {
      final c = Primitives.cube()..edges.add((0, 3));
      final m = SolidifyModifier().apply(c);
      expect(m.edges.length, 1);
    });

    test('roundtrip json', () {
      final r = MeshModifier.fromJson(SolidifyModifier(thickness: 0.42).toJson()) as SolidifyModifier;
      expect(r.thickness, 0.42);
      expect(r.clone().thickness, 0.42);
    });
  });

  test('unknown modifier type throws', () {
    expect(() => MeshModifier.fromJson({'type': 'wat'}), throwsArgumentError);
  });

  test('enabled flag skips apply in object evaluation', () {
    // covered via scene test; here just assert flag lives on the modifier
    final m = MirrorModifier()..enabled = false;
    expect(m.enabled, isFalse);
  });
}
