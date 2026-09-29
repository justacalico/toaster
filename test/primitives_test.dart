import 'package:flutter_test/flutter_test.dart';
import 'package:toaster/core/primitives.dart';
import 'package:toaster/core/vec3.dart';

void main() {
  test('all named primitives build non-empty meshes', () {
    for (final name in Primitives.names) {
      final m = Primitives.build(name);
      expect(m.vertices, isNotEmpty, reason: name);
      expect(m.faces, isNotEmpty, reason: name);
    }
    expect(Primitives.build('Nonsense').faces.length, 6); // default cube
  });

  test('cube is 8 verts, 6 quads, centered', () {
    final m = Primitives.cube(size: 2);
    expect(m.vertices.length, 8);
    expect(m.faces.length, 6);
    expect(m.centroid, Vec3.zero);
    expect(m.bounds.$2.x, 1);
  });

  test('plane is a single quad at z=0', () {
    final m = Primitives.plane();
    expect(m.faces.single.length, 4);
    for (final v in m.vertices) {
      expect(v.z, 0);
    }
  });

  test('circle is a single n-gon', () {
    final m = Primitives.circle(segments: 16);
    expect(m.faces.single.length, 16);
    expect(m.vertices.length, 16);
  });

  test('uv sphere is closed and welded at poles', () {
    final m = Primitives.uvSphere(segments: 12, rings: 6);
    expect(m.faces.length, 12 * 4 + 24); // rings-2 quads + 2 tri caps
    for (final v in m.vertices) {
      expect(v.length, closeTo(1, 1e-6));
    }
    final edgeFaces = m.edgeFaceMap();
    for (final adj in edgeFaces.values) {
      expect(adj.length, 2);
    }
  });

  test('ico sphere subdivides and stays spherical', () {
    final m0 = Primitives.icoSphere(subdivisions: 0);
    expect(m0.faces.length, 20);
    final m1 = Primitives.icoSphere(subdivisions: 1);
    expect(m1.faces.length, 80);
    for (final v in m1.vertices) {
      expect(v.length, closeTo(1, 1e-6));
    }
  });

  test('cylinder has side quads and caps', () {
    final m = Primitives.cylinder(segments: 8);
    expect(m.faces.length, 8 + 2);
    expect(m.bounds.$2.z, 1);
  });

  test('cone with r2=0 has apex tris', () {
    final m = Primitives.cone(segments: 8);
    final tris = m.faces.where((f) => f.length == 3).length;
    expect(tris, 8);
  });

  test('cone with r2>0 is a truncated cone (quads)', () {
    final m = Primitives.cone(segments: 8, radius2: 0.5);
    final quads = m.faces.where((f) => f.length == 4).length;
    expect(quads, 8);
  });

  test('torus topology', () {
    final m = Primitives.torus(majorSegments: 8, minorSegments: 4);
    expect(m.vertices.length, 32);
    expect(m.faces.length, 32);
    for (final f in m.faces) {
      expect(f.length, 4);
    }
  });

  test('grid is a subdivided plane', () {
    final m = Primitives.grid(subdivisions: 4);
    expect(m.vertices.length, 25);
    expect(m.faces.length, 16);
  });

  test('monkey is a merged multi-part mesh', () {
    final m = Primitives.monkey();
    expect(m.vertices.length, greaterThan(200));
    // every vert belongs to a face
    final used = m.faces.expand((f) => f).toSet();
    expect(used.length, m.vertices.length);
  });
}
