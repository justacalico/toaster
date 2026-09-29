import 'dart:math' as math;

import 'mesh.dart';
import 'vec3.dart';

/// Primitive mesh generators. All are centered at the origin, Z-up.
class Primitives {
  Primitives._(); // coverage:ignore-line

  static const names = [
    'Cube',
    'Plane',
    'Circle',
    'UV Sphere',
    'Ico Sphere',
    'Cylinder',
    'Cone',
    'Torus',
    'Grid',
    'Monkey',
  ];

  static Mesh build(String name) => switch (name) {
        'Plane' => plane(),
        'Circle' => circle(),
        'UV Sphere' => uvSphere(),
        'Ico Sphere' => icoSphere(),
        'Cylinder' => cylinder(),
        'Cone' => cone(),
        'Torus' => torus(),
        'Grid' => grid(),
        'Monkey' => monkey(),
        _ => cube(),
      };

  static Mesh cube({double size = 2}) {
    final h = size / 2;
    return Mesh(
      vertices: [
        Vec3(-h, -h, -h), Vec3(h, -h, -h), Vec3(h, h, -h), Vec3(-h, h, -h), //
        Vec3(-h, -h, h), Vec3(h, -h, h), Vec3(h, h, h), Vec3(-h, h, h),
      ],
      faces: [
        [0, 3, 2, 1], // bottom
        [4, 5, 6, 7], // top
        [0, 1, 5, 4], // -y
        [1, 2, 6, 5], // +x
        [2, 3, 7, 6], // +y
        [3, 0, 4, 7], // -x
      ],
    );
  }

  static Mesh plane({double size = 2}) {
    final h = size / 2;
    return Mesh(
      vertices: [Vec3(-h, -h, 0), Vec3(h, -h, 0), Vec3(h, h, 0), Vec3(-h, h, 0)],
      faces: [
        [0, 1, 2, 3]
      ],
    );
  }

  static Mesh circle({int segments = 32, double radius = 1}) {
    final verts = List.generate(segments, (i) {
      final a = i * 2 * math.pi / segments;
      return Vec3(math.cos(a) * radius, math.sin(a) * radius, 0);
    });
    return Mesh(vertices: verts, faces: [List.generate(segments, (i) => i)]);
  }

  static Mesh uvSphere({int segments = 32, int rings = 16, double radius = 1}) {
    final verts = <Vec3>[];
    final faces = <List<int>>[];
    for (var r = 0; r <= rings; r++) {
      final phi = r * math.pi / rings;
      for (var s = 0; s < segments; s++) {
        final theta = s * 2 * math.pi / segments;
        verts.add(Vec3(
          math.sin(phi) * math.cos(theta) * radius,
          math.sin(phi) * math.sin(theta) * radius,
          math.cos(phi) * radius,
        ));
      }
    }
    for (var r = 0; r < rings; r++) {
      for (var s = 0; s < segments; s++) {
        final a = r * segments + s;
        final b = r * segments + (s + 1) % segments;
        final c = (r + 1) * segments + (s + 1) % segments;
        final d = (r + 1) * segments + s;
        if (r == 0) {
          faces.add([a, c, d]);
        } else if (r == rings - 1) {
          faces.add([a, b, d]);
        } else {
          faces.add([a, b, c, d]);
        }
      }
    }
    return Mesh(vertices: verts, faces: faces)..weld(1e-6);
  }

  static Mesh icoSphere({int subdivisions = 2, double radius = 1}) {
    final t = (1 + math.sqrt(5)) / 2;
    final raw = [
      Vec3(-1, t, 0), Vec3(1, t, 0), Vec3(-1, -t, 0), Vec3(1, -t, 0), //
      Vec3(0, -1, t), Vec3(0, 1, t), Vec3(0, -1, -t), Vec3(0, 1, -t),
      Vec3(t, 0, -1), Vec3(t, 0, 1), Vec3(-t, 0, -1), Vec3(-t, 0, 1),
    ];
    var mesh = Mesh(
      vertices: raw.map((v) => v.normalized() * radius).toList(),
      faces: [
        [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
        [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
        [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
        [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
      ],
    );
    for (var i = 0; i < subdivisions; i++) {
      mesh = _subdivideTris(mesh);
      for (var j = 0; j < mesh.vertices.length; j++) {
        mesh.vertices[j] = mesh.vertices[j].normalized() * radius;
      }
    }
    return mesh;
  }

  static Mesh _subdivideTris(Mesh m) {
    final mid = <(int, int), int>{};
    int midpoint(int a, int b) {
      final key = a < b ? (a, b) : (b, a);
      return mid.putIfAbsent(key, () {
        m.vertices.add((m.vertices[a] + m.vertices[b]) / 2);
        return m.vertices.length - 1;
      });
    }

    final newFaces = <List<int>>[];
    for (final f in m.faces) {
      final m01 = midpoint(f[0], f[1]);
      final m12 = midpoint(f[1], f[2]);
      final m20 = midpoint(f[2], f[0]);
      newFaces.addAll([
        [f[0], m01, m20],
        [f[1], m12, m01],
        [f[2], m20, m12],
        [m01, m12, m20],
      ]);
    }
    m.faces
      ..clear()
      ..addAll(newFaces);
    return m;
  }

  static Mesh cylinder({int segments = 32, double radius = 1, double depth = 2}) {
    final h = depth / 2;
    final verts = <Vec3>[];
    for (var z = -1; z <= 1; z += 2) {
      for (var s = 0; s < segments; s++) {
        final a = s * 2 * math.pi / segments;
        verts.add(Vec3(math.cos(a) * radius, math.sin(a) * radius, h * z));
      }
    }
    final faces = <List<int>>[];
    for (var s = 0; s < segments; s++) {
      final n = (s + 1) % segments;
      faces.add([s, n, segments + n, segments + s]);
    }
    faces.add(List.generate(segments, (i) => segments - 1 - i));
    faces.add(List.generate(segments, (i) => segments + i));
    return Mesh(vertices: verts, faces: faces);
  }

  static Mesh cone({int segments = 32, double radius1 = 1, double radius2 = 0, double depth = 2}) {
    final h = depth / 2;
    final verts = <Vec3>[];
    for (var s = 0; s < segments; s++) {
      final a = s * 2 * math.pi / segments;
      verts.add(Vec3(math.cos(a) * radius1, math.sin(a) * radius1, -h));
    }
    final topCenter = verts.length;
    if (radius2 > 0) {
      for (var s = 0; s < segments; s++) {
        final a = s * 2 * math.pi / segments;
        verts.add(Vec3(math.cos(a) * radius2, math.sin(a) * radius2, h));
      }
    } else {
      verts.add(Vec3(0, 0, h));
    }
    final faces = <List<int>>[];
    for (var s = 0; s < segments; s++) {
      final n = (s + 1) % segments;
      if (radius2 > 0) {
        faces.add([s, n, segments + 1 + n, segments + 1 + s]);
      } else {
        faces.add([s, n, topCenter]);
      }
    }
    faces.add(List.generate(segments, (i) => segments - 1 - i));
    if (radius2 > 0) {
      faces.add(List.generate(segments, (i) => segments + 1 + i));
    }
    return Mesh(vertices: verts, faces: faces);
  }

  static Mesh torus({
    int majorSegments = 48,
    int minorSegments = 12,
    double majorRadius = 1,
    double minorRadius = 0.25,
  }) {
    final verts = <Vec3>[];
    final faces = <List<int>>[];
    for (var i = 0; i < majorSegments; i++) {
      final u = i * 2 * math.pi / majorSegments;
      for (var j = 0; j < minorSegments; j++) {
        final v = j * 2 * math.pi / minorSegments;
        final r = majorRadius + minorRadius * math.cos(v);
        verts.add(Vec3(r * math.cos(u), r * math.sin(u), minorRadius * math.sin(v)));
      }
    }
    for (var i = 0; i < majorSegments; i++) {
      final ni = (i + 1) % majorSegments;
      for (var j = 0; j < minorSegments; j++) {
        final nj = (j + 1) % minorSegments;
        faces.add([
          i * minorSegments + j,
          ni * minorSegments + j,
          ni * minorSegments + nj,
          i * minorSegments + nj,
        ]);
      }
    }
    return Mesh(vertices: verts, faces: faces);
  }

  static Mesh grid({double size = 2, int subdivisions = 10}) {
    final verts = <Vec3>[];
    final faces = <List<int>>[];
    final n = subdivisions;
    for (var y = 0; y <= n; y++) {
      for (var x = 0; x <= n; x++) {
        verts.add(Vec3(-size / 2 + size * x / n, -size / 2 + size * y / n, 0));
      }
    }
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final a = y * (n + 1) + x;
        faces.add([a, a + 1, a + n + 2, a + n + 1]);
      }
    }
    return Mesh(vertices: verts, faces: faces);
  }

  /// A low-poly stand-in for Suzanne: a stylized monkey face built from
  /// a sphere head with ear and snout geometry merged in.
  static Mesh monkey() {
    final head = uvSphere(segments: 24, rings: 12, radius: 0.9);
    // squash the head a little
    for (var i = 0; i < head.vertices.length; i++) {
      final v = head.vertices[i];
      head.vertices[i] = Vec3(v.x * 0.9, v.y * 0.75, v.z);
    }
    final mesh = head;
    int append(Mesh other) {
      final base = mesh.vertices.length;
      mesh.vertices.addAll(other.vertices);
      for (final f in other.faces) {
        mesh.faces.add(f.map((v) => v + base).toList());
      }
      return base;
    }

    // ears
    for (final side in [-1.0, 1.0]) {
      final ear = cylinder(segments: 12, radius: 0.35, depth: 0.2);
      ear.transform(Mat4.rotationZ(side * 0.5));
      ear.transform(Mat4.translation(Vec3(side * 0.95, 0, 0.3)));
      append(ear);
    }
    // eyes
    for (final side in [-1.0, 1.0]) {
      final eye = uvSphere(segments: 8, rings: 6, radius: 0.15);
      eye.transform(Mat4.translation(Vec3(side * 0.3, -0.65, 0.35)));
      append(eye);
    }
    // snout
    final snout = uvSphere(segments: 12, rings: 8, radius: 0.4);
    for (var i = 0; i < snout.vertices.length; i++) {
      final v = snout.vertices[i];
      snout.vertices[i] = Vec3(v.x * 1.2, v.y * 0.7, v.z * 0.7);
    }
    snout.transform(Mat4.translation(const Vec3(0, -0.55, -0.35)));
    append(snout);
    return mesh;
  }
}
