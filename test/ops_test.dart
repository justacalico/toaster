import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:toaster/core/mesh.dart';
import 'package:toaster/core/ops.dart';
import 'package:toaster/core/primitives.dart';
import 'package:toaster/core/vec3.dart';

void main() {
  group('extrude', () {
    test('extrudeFaces creates walls and returns cap verts', () {
      final m = Primitives.cube();
      final moved = MeshOps.extrudeFaces(m, {1}); // top face
      expect(moved.length, 4);
      expect(m.faces.length, 10); // 6 + 4 walls
      expect(m.vertices.length, 12);
      // walls are quads
      for (var i = 6; i < 10; i++) {
        expect(m.faces[i].length, 4);
      }
    });

    test('extrudeVertices creates loose edges', () {
      final m = Primitives.cube();
      final moved = MeshOps.extrudeVertices(m, {0, 1});
      expect(moved.length, 2);
      expect(m.edges.length, 2);
    });

    test('extrudeEdges builds a face', () {
      final m = Primitives.cube();
      final moved = MeshOps.extrudeEdges(m, {0});
      expect(moved.length, 2);
      expect(m.faces.length, 7);
      // out-of-range index ignored
      expect(MeshOps.extrudeEdges(m, {999}), isEmpty);
    });
  });

  group('inset', () {
    test('insetFaces shrinks the face inward', () {
      final m = Primitives.cube();
      final inner = MeshOps.insetFaces(m, {1}, 0.25);
      expect(inner.length, 4);
      expect(m.faces.length, 10);
      // inner verts closer to face center than originals
      final c = Vec3(0, 0, 1);
      for (final v in inner) {
        expect(m.vertices[v].distanceTo(c), lessThan(1.5));
      }
    });
  });

  group('subdivide', () {
    test('quad face becomes 4 quads', () {
      final m = Primitives.cube();
      MeshOps.subdivide(m, {1});
      expect(m.faces.length, 5 + 4); // 5 untouched + 4 quads
      // 8 orig + 4 edge mids + 1 center
      expect(m.vertices.length, 13);
    });

    test('two adjacent faces share the midpoint', () {
      final m = Primitives.cube();
      MeshOps.subdivide(m, {1, 2});
      // 8 + 1 center *2 + unique edge midpoints (4+4 shared 1) = 17
      expect(m.vertices.length, 8 + 7 + 2);
      expect(m.faces.length, 4 + 8);
    });

    test('subdivideEdges splits loose edges only', () {
      final m = Mesh(
        vertices: [Vec3.zero, const Vec3(2, 0, 0)],
        edges: [(0, 1)],
      );
      final created = MeshOps.subdivideEdges(m, {0});
      expect(created.single, 2);
      expect(m.edges.length, 2);
      expect(m.vertices[2], const Vec3(1, 0, 0));
      // face edges are not loose, ignored
      final c = Primitives.cube();
      expect(MeshOps.subdivideEdges(c, {0}), isEmpty);
    });
  });

  group('fill', () {
    test('creates ordered n-gon', () {
      final m = Mesh(vertices: [
        const Vec3(0, 0, 0),
        const Vec3(1, 0, 0),
        const Vec3(1, 1, 0),
        const Vec3(0, 1, 0),
      ]);
      // deliberately scrambled selection order
      final fi = MeshOps.fill(m, {2, 0, 3, 1})!;
      final f = m.faces[fi];
      expect(f.length, 4);
      // ordered around the face: consecutive verts are neighbors
      String edgeKey(int a, int b) => a < b ? '$a-$b' : '$b-$a';
      final es = {for (var i = 0; i < 4; i++) edgeKey(f[i], f[(i + 1) % 4])};
      expect(es.contains('0-1'), isTrue);
      expect(es.contains('1-2'), isTrue);
      expect(es.contains('2-3'), isTrue);
      expect(es.contains('0-3'), isTrue);
    });

    test('rejects degenerate input', () {
      final m = Mesh(vertices: [Vec3.zero, Vec3.unitX]);
      expect(MeshOps.fill(m, {0, 1}), isNull);
      // collinear
      final m2 = Mesh(vertices: [Vec3.zero, Vec3.unitX, const Vec3(2, 0, 0)]);
      expect(MeshOps.fill(m2, {0, 1, 2}), isNull);
    });
  });

  group('delete', () {
    test('deleteFaces removes by index', () {
      final m = Primitives.cube();
      MeshOps.deleteFaces(m, {0, 2});
      expect(m.faces.length, 4);
    });

    test('deleteVertices removes dependent geometry', () {
      final m = Primitives.cube();
      MeshOps.deleteVertices(m, {0});
      // faces 0 (bottom), 2 (-y), 5 (-x) touch vert 0
      expect(m.faces.length, 3);
      expect(m.vertices.length, 7);
    });

    test('deleteEdges removes faces sharing the edge', () {
      final m = Primitives.cube();
      MeshOps.deleteEdges(m, {0});
      expect(m.faces.length, 4); // 2 faces shared edge 0
      // out of range is a no-op
      MeshOps.deleteEdges(m, {999});
      expect(m.faces.length, 4);
    });
  });

  group('mergeByDistance', () {
    test('collapses close verts', () {
      final m = Mesh(
        vertices: [Vec3.zero, const Vec3(0.0005, 0, 0), const Vec3(1, 0, 0), const Vec3(0, 1, 0)],
        faces: [
          [0, 2, 3],
          [1, 2, 3],
        ],
      );
      MeshOps.mergeByDistance(m, {0, 1}, 0.01);
      expect(m.vertices.length, 3);
    });

    test('mergeAtCenter-like full weld', () {
      final m = Mesh(
        vertices: [Vec3.zero, const Vec3(0.0005, 0, 0)],
        edges: [(0, 1)],
      );
      MeshOps.mergeByDistance(m, {0, 1}, 0.01);
      expect(m.vertices.length, 1);
    });
  });

  test('flipNormals reverses winding', () {
    final m = Primitives.cube();
    MeshOps.flipNormals(m, {1});
    expect(m.faceNormal(1).z, -1);
    // out-of-range index ignored
    MeshOps.flipNormals(m, {99});
  });

  group('transform helpers', () {
    final cube = Primitives.cube();

    test('transformVerts applies matrix to subset', () {
      final m = cube.clone();
      MeshOps.transformVerts(m, [0], Mat4.translation(const Vec3(0, 0, 5)));
      expect(m.vertices[0].z, 4);
      expect(m.vertices[1].z, -1);
    });

    test('translateVerts', () {
      final m = cube.clone();
      MeshOps.translateVerts(m, [0, 1], const Vec3(1, 0, 0));
      expect(m.vertices[0].x, 0);
      expect(m.vertices[2].x, 1);
    });

    test('rotateVerts around pivot', () {
      final m = cube.clone();
      MeshOps.rotateVerts(m, [4], Vec3.zero, Vec3.unitZ, math.pi / 2);
      expect(m.vertices[4].x, closeTo(1, 1e-9)); // (-1,-1,1) -> (1,-1,1)
      expect(m.vertices[4].y, closeTo(-1, 1e-9));
    });

    test('scaleVerts around pivot', () {
      final m = cube.clone();
      MeshOps.scaleVerts(m, [4], Vec3.zero, const Vec3(2, 1, 1));
      expect(m.vertices[4].x, -2);
      expect(m.vertices[4].y, -1);
    });
  });
}
