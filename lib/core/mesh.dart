import 'vec3.dart';

/// A polygon mesh. Faces are n-gons; `edges` holds loose edges that
/// belong to no face (created by vertex extrudes, wire objects, etc).
class Mesh {
  final List<Vec3> vertices;
  final List<List<int>> faces;
  final List<(int, int)> edges;

  Mesh({List<Vec3>? vertices, List<List<int>>? faces, List<(int, int)>? edges})
      : vertices = vertices ?? [],
        faces = faces ?? [],
        edges = edges ?? [];

  Mesh clone() => Mesh(
        vertices: vertices.map((v) => Vec3(v.x, v.y, v.z)).toList(),
        faces: faces.map((f) => List<int>.of(f)).toList(),
        edges: List.of(edges),
      );

  /// All edges: face perimeter edges plus loose edges.
  Set<(int, int)> allEdges() {
    final set = <(int, int)>{};
    for (final f in faces) {
      for (var i = 0; i < f.length; i++) {
        final a = f[i], b = f[(i + 1) % f.length];
        set.add(a < b ? (a, b) : (b, a));
      }
    }
    for (final e in edges) {
      set.add(e.$1 < e.$2 ? e : (e.$2, e.$1));
    }
    return set;
  }

  Vec3 faceNormal(int fi) {
    final f = faces[fi];
    var n = Vec3.zero;
    for (var i = 0; i < f.length; i++) {
      final a = vertices[f[i]], b = vertices[f[(i + 1) % f.length]];
      n += Vec3(
        (a.y - b.y) * (a.z + b.z),
        (a.z - b.z) * (a.x + b.x),
        (a.x - b.x) * (a.y + b.y),
      );
    }
    return n.normalized();
  }

  Vec3 faceCenter(int fi) {
    var c = Vec3.zero;
    for (final vi in faces[fi]) {
      c += vertices[vi];
    }
    return c / faces[fi].length.toDouble();
  }

  /// Average vertex normals for smooth shading.
  List<Vec3> vertexNormals() {
    final acc = List<Vec3>.filled(vertices.length, Vec3.zero);
    for (var fi = 0; fi < faces.length; fi++) {
      final n = faceNormal(fi);
      for (final vi in faces[fi]) {
        acc[vi] += n;
      }
    }
    return acc.map((v) => v.normalized()).toList();
  }

  /// Fan triangulation of all faces. Returns (faceIndex, [a,b,c]) pairs.
  List<(int, List<int>)> triangulated() {
    final out = <(int, List<int>)>[];
    for (var fi = 0; fi < faces.length; fi++) {
      final f = faces[fi];
      for (var i = 1; i + 1 < f.length; i++) {
        out.add((fi, [f[0], f[i], f[i + 1]]));
      }
    }
    return out;
  }

  void transform(Mat4 m) {
    for (var i = 0; i < vertices.length; i++) {
      vertices[i] = m.transformPoint(vertices[i]);
    }
  }

  Vec3 get centroid {
    if (vertices.isEmpty) return Vec3.zero;
    var c = Vec3.zero;
    for (final v in vertices) {
      c += v;
    }
    return c / vertices.length.toDouble();
  }

  (Vec3, Vec3) get bounds {
    if (vertices.isEmpty) return (Vec3.zero, Vec3.zero);
    var lo = vertices[0], hi = vertices[0];
    for (final v in vertices) {
      lo = lo.min(v);
      hi = hi.max(v);
    }
    return (lo, hi);
  }

  /// Welds vertices closer than [threshold], rewriting faces and edges.
  /// Returns the old->new index map.
  List<int> weld(double threshold) {
    final newVerts = <Vec3>[];
    final remap = List<int>.filled(vertices.length, -1);
    for (var i = 0; i < vertices.length; i++) {
      var found = -1;
      for (var j = 0; j < newVerts.length; j++) {
        if (newVerts[j].distanceTo(vertices[i]) < threshold) {
          found = j;
          break;
        }
      }
      if (found < 0) {
        found = newVerts.length;
        newVerts.add(vertices[i]);
      }
      remap[i] = found;
    }
    vertices
      ..clear()
      ..addAll(newVerts);
    for (var fi = 0; fi < faces.length; fi++) {
      faces[fi] = faces[fi].map((v) => remap[v]).toList();
      // drop degenerate repeats inside a face
      faces[fi] = faces[fi].fold<List<int>>([], (acc, v) {
        if (acc.isEmpty || acc.last != v) acc.add(v);
        return acc;
      });
      if (faces[fi].length > 1 && faces[fi].first == faces[fi].last) {
        faces[fi].removeLast();
      }
    }
    faces.removeWhere((f) => f.length < 3);
    for (var i = 0; i < edges.length; i++) {
      var e = edges[i];
      e = (remap[e.$1], remap[e.$2]);
      edges[i] = e.$1 < e.$2 ? e : (e.$2, e.$1);
    }
    edges.removeWhere((e) => e.$1 == e.$2);
    // dedupe edges
    final seen = <(int, int)>{};
    edges.retainWhere(seen.add);
    return remap;
  }

  /// Removes unreferenced vertices and remaps faces/edges.
  List<int> compact() {
    final used = List<bool>.filled(vertices.length, false);
    for (final f in faces) {
      for (final v in f) {
        used[v] = true;
      }
    }
    for (final e in edges) {
      used[e.$1] = used[e.$2] = true;
    }
    final remap = List<int>.filled(vertices.length, -1);
    final newVerts = <Vec3>[];
    for (var i = 0; i < vertices.length; i++) {
      if (used[i]) {
        remap[i] = newVerts.length;
        newVerts.add(vertices[i]);
      }
    }
    vertices
      ..clear()
      ..addAll(newVerts);
    for (var i = 0; i < faces.length; i++) {
      faces[i] = faces[i].map((v) => remap[v]).toList();
    }
    for (var i = 0; i < edges.length; i++) {
      edges[i] = (remap[edges[i].$1], remap[edges[i].$2]);
    }
    return remap;
  }

  int addVertex(Vec3 v) {
    vertices.add(v);
    return vertices.length - 1;
  }

  /// Map of edge -> adjacent face indices.
  Map<(int, int), List<int>> edgeFaceMap() {
    final map = <(int, int), List<int>>{};
    for (var fi = 0; fi < faces.length; fi++) {
      final f = faces[fi];
      for (var i = 0; i < f.length; i++) {
        final a = f[i], b = f[(i + 1) % f.length];
        final key = a < b ? (a, b) : (b, a);
        map.putIfAbsent(key, () => []).add(fi);
      }
    }
    return map;
  }
}
