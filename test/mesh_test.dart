import 'package:flutter_test/flutter_test.dart';
import 'package:toaster/core/mesh.dart';
import 'package:toaster/core/primitives.dart';
import 'package:toaster/core/vec3.dart';

void main() {
  group('Mesh', () {
    test('clone is deep', () {
      final m = Primitives.cube();
      final c = m.clone();
      c.vertices[0] = const Vec3(9, 9, 9);
      c.faces[0] = [0, 0, 0, 0];
      c.edges.add((0, 1));
      expect(m.vertices[0], const Vec3(-1, -1, -1));
      expect(m.faces[0], [0, 3, 2, 1]);
      expect(m.edges, isEmpty);
    });

    test('allEdges covers face perimeter plus loose edges', () {
      final m = Primitives.cube();
      expect(m.allEdges().length, 12);
      m.edges.add((0, 7));
      expect(m.allEdges().length, 13);
    });

    test('faceNormal points outward for a cube', () {
      final m = Primitives.cube();
      expect(m.faceNormal(1), Vec3.unitZ); // top face
      expect(m.faceNormal(0).z, -1.0);
    });

    test('faceCenter and centroid', () {
      final m = Primitives.cube();
      expect(m.faceCenter(1), const Vec3(0, 0, 1));
      expect(m.centroid, Vec3.zero);
      expect(Mesh().centroid, Vec3.zero);
    });

    test('vertexNormals are normalized', () {
      final m = Primitives.cube();
      for (final n in m.vertexNormals()) {
        expect(n.length, closeTo(1, 1e-9));
      }
    });

    test('triangulated fans n-gons', () {
      final m = Primitives.cube();
      // 6 quads -> 12 tris
      expect(m.triangulated().length, 12);
      expect(m.triangulated().first.$1, 0);
      expect(m.triangulated().first.$2.length, 3);
    });

    test('transform applies matrix', () {
      final m = Primitives.cube();
      m.transform(Mat4.translation(const Vec3(5, 0, 0)));
      expect(m.centroid, const Vec3(5, 0, 0));
    });

    test('bounds', () {
      final m = Primitives.cube(size: 4);
      final (lo, hi) = m.bounds;
      expect(lo, const Vec3(-2, -2, -2));
      expect(hi, const Vec3(2, 2, 2));
      expect(Mesh().bounds, (Vec3.zero, Vec3.zero));
    });

    test('weld merges near verts and keeps maps consistent', () {
      // two stacked cubes sharing a face plane -> 16 verts weld to 12
      final m = Primitives.cube();
      m.transform(Mat4.translation(const Vec3(0, 0, 0)));
      final top = Primitives.cube();
      top.transform(Mat4.translation(const Vec3(0, 0, 2)));
      final base = m.vertices.length;
      m.vertices.addAll(top.vertices);
      m.faces.addAll(top.faces.map((f) => f.map((v) => v + base).toList()));
      expect(m.vertices.length, 16);
      final map = m.weld(0.01);
      expect(m.vertices.length, 12);
      expect(map[0], 0);
      for (final f in m.faces) {
        for (final v in f) {
          expect(v, lessThan(m.vertices.length));
        }
      }
    });

    test('compact drops unused verts', () {
      final m = Primitives.cube();
      m.faces.removeRange(1, 6); // keep only bottom face
      m.edges.clear();
      m.compact();
      expect(m.vertices.length, 4);
      expect(m.faces.single.length, 4);
    });

    test('compact keeps loose edge endpoints', () {
      final m = Mesh(vertices: [Vec3.zero, const Vec3(1, 0, 0)], edges: [(0, 1)]);
      m.compact();
      expect(m.vertices.length, 2);
      expect(m.edges.single, (0, 1));
    });

    test('edgeFaceMap counts adjacency', () {
      final m = Primitives.cube();
      final map = m.edgeFaceMap();
      for (final e in map.values) {
        expect(e.length, 2); // closed cube: every edge has 2 faces
      }
    });
  });
}
