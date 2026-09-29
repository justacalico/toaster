import 'dart:math' as math;

import 'mesh.dart';
import 'vec3.dart';

/// Mesh editing operations. Pure functions over [Mesh] + index selections.
class MeshOps {
  MeshOps._(); // coverage:ignore-line

  /// Extrudes the given faces as a region: shared vertices are duplicated
  /// once, edges between two selected faces become interior (no wall),
  /// and walls are only built on the selection boundary. Returns the
  /// vertex indices of the extruded cap (for the grab session).
  static List<int> extrudeFaces(Mesh m, Set<int> faceIdx) {
    // count how many selected faces touch each perimeter edge
    final edgeUse = <(int, int), int>{};
    final dirEdge = <(int, int), (int, int)>{};
    for (final fi in faceIdx) {
      final f = m.faces[fi];
      for (var i = 0; i < f.length; i++) {
        final a = f[i], b = f[(i + 1) % f.length];
        final key = a < b ? (a, b) : (b, a);
        edgeUse[key] = (edgeUse[key] ?? 0) + 1;
        dirEdge[key] = (a, b);
      }
    }
    // one duplicate per source vertex, shared across the whole region
    final dupOf = <int, int>{};
    int dup(int v) => dupOf.putIfAbsent(v, () => m.addVertex(m.vertices[v]));

    for (final fi in faceIdx) {
      final f = m.faces[fi];
      final cap = f.map(dup).toList();
      // side walls only on boundary edges (used by exactly one selected face)
      for (var i = 0; i < f.length; i++) {
        final a = f[i], b = f[(i + 1) % f.length];
        final key = a < b ? (a, b) : (b, a);
        if ((edgeUse[key] ?? 0) == 1) {
          final (sa, sb) = dirEdge[key]!;
          m.faces.add([sa, sb, dup(sb), dup(sa)]);
        }
      }
      // cap replaces the original face
      m.faces[fi] = cap;
    }
    return dupOf.values.toList();
  }

  /// Extrudes selected vertices (creates loose edges).
  static List<int> extrudeVertices(Mesh m, Set<int> vertIdx) {
    final moved = <int>[];
    for (final v in vertIdx.toList()..sort()) {
      final nv = m.addVertex(m.vertices[v]);
      m.edges.add((v, nv));
      moved.add(nv);
    }
    return moved;
  }

  /// Extrudes selected edges into faces.
  static List<int> extrudeEdges(Mesh m, Set<int> edgeIdx) {
    final all = m.allEdges().toList();
    final moved = <int>[];
    for (final ei in edgeIdx.toList()..sort()) {
      if (ei >= all.length) continue;
      final (a, b) = all[ei];
      final na = m.addVertex(m.vertices[a]);
      final nb = m.addVertex(m.vertices[b]);
      m.faces.add([a, b, nb, na]);
      m.edges.remove((a, b));
      moved.addAll([na, nb]);
    }
    return moved;
  }

  /// Insets faces by a 0..1 scale toward their centroid.
  static List<int> insetFaces(Mesh m, Set<int> faceIdx, double amount) {
    final inner = <int>[];
    for (final fi in faceIdx.toList()..sort()) {
      final f = m.faces[fi];
      final c = m.faceCenter(fi);
      final dup = <int>[];
      for (final v in f) {
        dup.add(m.addVertex(m.vertices[v].lerp(c, amount.clamp(0.0, 0.95))));
      }
      for (var i = 0; i < f.length; i++) {
        final a = f[i], b = f[(i + 1) % f.length];
        m.faces.add([a, b, dup[(i + 1) % f.length], dup[i]]);
      }
      m.faces[fi] = dup;
      inner.addAll(dup);
    }
    return inner;
  }

  /// Splits each selected face into quads (edge midpoints + face center).
  /// Faces sharing an edge keep working since midpoints sit on the edge.
  /// Returns the indices of the created faces.
  static Set<int> subdivide(Mesh m, Set<int> faceIdx) {
    final mids = <(int, int), int>{};
    int midpoint(int a, int b) {
      final key = a < b ? (a, b) : (b, a);
      return mids.putIfAbsent(key, () {
        m.vertices.add((m.vertices[a] + m.vertices[b]) / 2);
        return m.vertices.length - 1;
      });
    }

    final newFaces = <List<int>>[];
    final created = <int>{};
    for (var fi = 0; fi < m.faces.length; fi++) {
      if (!faceIdx.contains(fi)) {
        newFaces.add(m.faces[fi]);
        continue;
      }
      final f = m.faces[fi];
      final c = m.addVertex(m.faceCenter(fi));
      for (var i = 0; i < f.length; i++) {
        final prev = f[(i + f.length - 1) % f.length];
        final cur = f[i];
        final next = f[(i + 1) % f.length];
        created.add(newFaces.length);
        newFaces.add([cur, midpoint(cur, next), c, midpoint(prev, cur)]);
      }
    }
    m.faces
      ..clear()
      ..addAll(newFaces);
    return created;
  }

  /// Splits edges at their midpoint. Loose edges break in two; edges that
  /// belong to faces get the midpoint inserted into the face loop.
  /// Returns the created vertex indices.
  static Set<int> subdivideEdges(Mesh m, Set<int> edgeIdx) {
    final all = m.allEdges().toList();
    final mids = <(int, int), int>{};
    for (final ei in edgeIdx) {
      if (ei >= all.length) continue;
      final e = all[ei];
      mids[e] = m.addVertex((m.vertices[e.$1] + m.vertices[e.$2]) / 2);
    }
    // face edges: insert midpoint into each containing face's loop
    for (var fi = 0; fi < m.faces.length; fi++) {
      final f = m.faces[fi];
      final nf = <int>[];
      for (var i = 0; i < f.length; i++) {
        final a = f[i], b = f[(i + 1) % f.length];
        nf.add(a);
        final key = a < b ? (a, b) : (b, a);
        final mid = mids[key];
        if (mid != null) nf.add(mid);
      }
      if (nf.length != f.length) m.faces[fi] = nf;
    }
    // loose edges: break into two
    final loose = m.edges.toSet();
    for (final e in mids.keys) {
      if (loose.remove(e)) {
        final mid = mids[e]!;
        m.edges
          ..remove(e)
          ..add((e.$1, mid))
          ..add((mid, e.$2));
      }
    }
    return mids.values.toSet();
  }

  /// Builds an n-gon from a vertex set, ordered around the centroid.
  /// Returns the new face index, or null if fewer than 3 verts.
  static int? fill(Mesh m, Set<int> vertIdx) {
    if (vertIdx.length < 3) return null;
    final verts = vertIdx.toList();
    var c = Vec3.zero;
    for (final v in verts) {
      c += m.vertices[v];
    }
    c = c / verts.length.toDouble();
    // plane normal from any non-degenerate triplet
    var n = Vec3.zero;
    for (var i = 0; i < verts.length && n.length2 < 1e-12; i++) {
      for (var j = i + 1; j < verts.length && n.length2 < 1e-12; j++) {
        for (var k = j + 1; k < verts.length && n.length2 < 1e-12; k++) {
          n = (m.vertices[verts[j]] - m.vertices[verts[i]])
              .cross(m.vertices[verts[k]] - m.vertices[verts[i]]);
        }
      }
    }
    if (n.length2 < 1e-12) return null;
    n = n.normalized();
    final u = n.cross(Vec3.unitZ).length2 > 1e-9 ? n.cross(Vec3.unitZ).normalized() : Vec3.unitX;
    final v = n.cross(u);
    verts.sort((a, b) {
      final da = m.vertices[a] - c, db = m.vertices[b] - c;
      final aa = math.atan2(da.dot(v), da.dot(u));
      final ab = math.atan2(db.dot(v), db.dot(u));
      return aa.compareTo(ab);
    });
    m.faces.add(verts);
    return m.faces.length - 1;
  }

  /// Deletes faces by index.
  static void deleteFaces(Mesh m, Set<int> faceIdx) {
    final keep = <List<int>>[];
    for (var i = 0; i < m.faces.length; i++) {
      if (!faceIdx.contains(i)) keep.add(m.faces[i]);
    }
    m.faces
      ..clear()
      ..addAll(keep);
  }

  /// Deletes vertices (and any face/edge touching them), compacts indices.
  /// Returns old->new vertex map.
  static List<int> deleteVertices(Mesh m, Set<int> vertIdx) {
    m.faces.removeWhere((f) => f.any(vertIdx.contains));
    m.edges.removeWhere((e) => vertIdx.contains(e.$1) || vertIdx.contains(e.$2));
    final remap = List<int>.filled(m.vertices.length, -1);
    final keep = <Vec3>[];
    for (var i = 0; i < m.vertices.length; i++) {
      if (!vertIdx.contains(i)) {
        remap[i] = keep.length;
        keep.add(m.vertices[i]);
      }
    }
    m.vertices
      ..clear()
      ..addAll(keep);
    for (var i = 0; i < m.faces.length; i++) {
      m.faces[i] = m.faces[i].map((v) => remap[v]).toList();
    }
    for (var i = 0; i < m.edges.length; i++) {
      m.edges[i] = (remap[m.edges[i].$1], remap[m.edges[i].$2]);
    }
    return remap;
  }

  /// Deletes loose edges by index into allEdges().
  static void deleteEdges(Mesh m, Set<int> edgeIdx) {
    final all = m.allEdges().toList();
    final doomed = <(int, int)>{};
    for (final ei in edgeIdx) {
      if (ei < all.length) doomed.add(all[ei]);
    }
    // remove faces using doomed face-edges
    m.faces.removeWhere((f) {
      for (var i = 0; i < f.length; i++) {
        final a = f[i], b = f[(i + 1) % f.length];
        final key = a < b ? (a, b) : (b, a);
        if (doomed.contains(key)) return true;
      }
      return false;
    });
    m.edges.removeWhere(doomed.contains);
  }

  /// Moves verts toward each other; merges verts within [dist] of the
  /// first selected vertex ordering — a simple weld of the selection.
  static List<int> mergeByDistance(Mesh m, Set<int> vertIdx, double dist) {
    final sorted = vertIdx.toList()..sort();
    final remap = List<int>.generate(m.vertices.length, (i) => i);
    for (var i = 0; i < sorted.length; i++) {
      for (var j = i + 1; j < sorted.length; j++) {
        if (remap[sorted[j]] != sorted[j]) continue;
        if (m.vertices[sorted[i]].distanceTo(m.vertices[sorted[j]]) < dist) {
          remap[sorted[j]] = remap[sorted[i]];
        }
      }
    }
    // collapse
    final newVerts = <Vec3>[];
    final finalMap = List<int>.filled(m.vertices.length, -1);
    for (var i = 0; i < m.vertices.length; i++) {
      final target = remap[i];
      if (target == i) {
        finalMap[i] = newVerts.length;
        newVerts.add(m.vertices[i]);
      }
    }
    for (var i = 0; i < m.vertices.length; i++) {
      if (finalMap[i] < 0) finalMap[i] = finalMap[remap[i]];
    }
    m.vertices
      ..clear()
      ..addAll(newVerts);
    for (var i = 0; i < m.faces.length; i++) {
      m.faces[i] = m.faces[i].map((v) => finalMap[v]).toSet().toList();
    }
    m.faces.removeWhere((f) => f.length < 3);
    // remap existing loose edges only; face perimeter edges are implicit
    final remapped = <(int, int)>{};
    for (final e in m.edges) {
      final a = finalMap[e.$1], b = finalMap[e.$2];
      if (a != b) remapped.add(a < b ? (a, b) : (b, a));
    }
    m.edges
      ..clear()
      ..addAll(remapped);
    return finalMap;
  }

  /// Flips winding of faces.
  static void flipNormals(Mesh m, Set<int> faceIdx) {
    for (final fi in faceIdx) {
      if (fi < m.faces.length) m.faces[fi] = m.faces[fi].reversed.toList();
    }
  }

  /// Applies a matrix to a subset of vertices (local space).
  static void transformVerts(Mesh m, Iterable<int> idx, Mat4 mat) {
    for (final i in idx) {
      m.vertices[i] = mat.transformPoint(m.vertices[i]);
    }
  }

  /// Moves verts by a delta.
  static void translateVerts(Mesh m, Iterable<int> idx, Vec3 delta) {
    for (final i in idx) {
      m.vertices[i] = m.vertices[i] + delta;
    }
  }

  /// Rotates verts around pivot on the given axis.
  static void rotateVerts(Mesh m, Iterable<int> idx, Vec3 pivot, Vec3 axis, double angle) {
    final mat = Mat4.translation(pivot) * Mat4.rotationAxis(axis.normalized(), angle) * Mat4.translation(-pivot);
    transformVerts(m, idx, mat);
  }

  /// Scales verts around pivot; [factor] is a vector for axis-constrained scale.
  static void scaleVerts(Mesh m, Iterable<int> idx, Vec3 pivot, Vec3 factor) {
    final mat = Mat4.translation(pivot) * Mat4.scaling(factor) * Mat4.translation(-pivot);
    transformVerts(m, idx, mat);
  }
}
