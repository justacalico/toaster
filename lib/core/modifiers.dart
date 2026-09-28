import 'mesh.dart';
import 'vec3.dart';

/// Non-destructive mesh modifier, applied in order by [SceneObject.evaluatedMesh].
abstract class MeshModifier {
  String get type;
  bool enabled = true;

  Mesh apply(Mesh input);

  MeshModifier clone();

  Map<String, dynamic> toJson();

  static MeshModifier fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'mirror' => MirrorModifier.fromJson(j),
        'array' => ArrayModifier.fromJson(j),
        'subdivision' => SubdivisionModifier.fromJson(j),
        'bevel' => BevelModifier.fromJson(j),
        'solidify' => SolidifyModifier.fromJson(j),
        _ => throw ArgumentError('unknown modifier ${j['type']}'),
      };

  void restoreCommon(Map<String, dynamic> j) {
    enabled = j['enabled'] as bool? ?? true;
  }
}

/// Mirrors geometry across a local axis plane.
class MirrorModifier extends MeshModifier {
  int axis; // 0=X, 1=Y, 2=Z
  bool merge;
  double mergeDistance;

  MirrorModifier({this.axis = 0, this.merge = true, this.mergeDistance = 0.001});

  @override
  String get type => 'mirror';

  @override
  Mesh apply(Mesh input) {
    final out = input.clone();
    final remap = List<int>.filled(input.vertices.length, -1);
    for (var i = 0; i < input.vertices.length; i++) {
      final v = input.vertices[i];
      final c = v.axisValue(axis);
      if (merge && c.abs() < mergeDistance) {
        out.vertices[i] = v.withAxis(axis, 0);
        remap[i] = i;
      } else {
        remap[i] = out.vertices.length;
        out.vertices.add(v.withAxis(axis, -c));
      }
    }
    final base = input.faces.length;
    for (var fi = 0; fi < base; fi++) {
      final f = input.faces[fi];
      // skip faces fully on the mirror plane
      if (merge && f.every((v) => input.vertices[v].axisValue(axis).abs() < mergeDistance)) {
        continue;
      }
      out.faces.add(f.map((v) => remap[v]).toList().reversed.toList());
    }
    final baseE = input.edges.length;
    for (var ei = 0; ei < baseE; ei++) {
      final e = input.edges[ei];
      if (merge &&
          input.vertices[e.$1].axisValue(axis).abs() < mergeDistance &&
          input.vertices[e.$2].axisValue(axis).abs() < mergeDistance) {
        continue;
      }
      out.edges.add((remap[e.$1], remap[e.$2]));
    }
    return out;
  }

  @override
  MirrorModifier clone() {
    final m = MirrorModifier(axis: axis, merge: merge, mergeDistance: mergeDistance);
    m.enabled = enabled;
    return m;
  }

  @override
  Map<String, dynamic> toJson() =>
      {'type': type, 'enabled': enabled, 'axis': axis, 'merge': merge, 'mergeDistance': mergeDistance};

  factory MirrorModifier.fromJson(Map<String, dynamic> j) {
    final m = MirrorModifier(
      axis: (j['axis'] as num?)?.toInt() ?? 0,
      merge: j['merge'] as bool? ?? true,
      mergeDistance: (j['mergeDistance'] as num?)?.toDouble() ?? 0.001,
    );
    m.restoreCommon(j);
    return m;
  }
}

/// Repeats the mesh in a line with an offset.
class ArrayModifier extends MeshModifier {
  int count;
  Vec3 constantOffset;
  bool useRelativeOffset;
  Vec3 relativeOffset;

  ArrayModifier({
    this.count = 2,
    this.constantOffset = Vec3.zero,
    this.useRelativeOffset = true,
    this.relativeOffset = const Vec3(1, 0, 0),
  });

  @override
  String get type => 'array';

  @override
  Mesh apply(Mesh input) {
    if (count <= 1) return input.clone();
    final out = input.clone();
    var step = constantOffset;
    if (useRelativeOffset) {
      final (lo, hi) = input.bounds;
      final size = hi - lo;
      step = size.mulVec(relativeOffset);
    }
    for (var copy = 1; copy < count; copy++) {
      final base = out.vertices.length;
      final off = step * copy.toDouble();
      for (final v in input.vertices) {
        out.vertices.add(v + off);
      }
      for (final f in input.faces) {
        out.faces.add(f.map((v) => v + base).toList());
      }
      for (final e in input.edges) {
        out.edges.add((e.$1 + base, e.$2 + base));
      }
    }
    return out;
  }

  @override
  ArrayModifier clone() {
    final m = ArrayModifier(
      count: count,
      constantOffset: constantOffset,
      useRelativeOffset: useRelativeOffset,
      relativeOffset: relativeOffset,
    );
    m.enabled = enabled;
    return m;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'enabled': enabled,
        'count': count,
        'constantOffset': constantOffset.toJson(),
        'useRelativeOffset': useRelativeOffset,
        'relativeOffset': relativeOffset.toJson(),
      };

  factory ArrayModifier.fromJson(Map<String, dynamic> j) {
    final m = ArrayModifier(
      count: (j['count'] as num?)?.toInt() ?? 2,
      constantOffset: j['constantOffset'] != null ? Vec3.fromJson(j['constantOffset'] as List) : Vec3.zero,
      useRelativeOffset: j['useRelativeOffset'] as bool? ?? true,
      relativeOffset:
          j['relativeOffset'] != null ? Vec3.fromJson(j['relativeOffset'] as List) : const Vec3(1, 0, 0),
    );
    m.restoreCommon(j);
    return m;
  }
}

/// Catmull-Clark subdivision. Handles n-gons, triangles, loose edges
/// and open boundaries.
class SubdivisionModifier extends MeshModifier {
  int levels;

  SubdivisionModifier({this.levels = 1});

  @override
  String get type => 'subdivision';

  @override
  Mesh apply(Mesh input) {
    var m = input.clone();
    for (var i = 0; i < levels; i++) {
      m = _cc(m);
    }
    return m;
  }

  Mesh _cc(Mesh m) {
    final facePoints = List.generate(m.faces.length, (i) => m.faceCenter(i));
    final edgeFaces = m.edgeFaceMap();
    final vertEdges = <int, List<(int, int)>>{};
    for (final e in edgeFaces.keys) {
      vertEdges.putIfAbsent(e.$1, () => []).add(e);
      vertEdges.putIfAbsent(e.$2, () => []).add(e);
    }
    final vertFaces = <int, List<int>>{};
    for (var fi = 0; fi < m.faces.length; fi++) {
      for (final v in m.faces[fi]) {
        vertFaces.putIfAbsent(v, () => []).add(fi);
      }
    }

    // edge points
    final edgePointIndex = <(int, int), int>{};
    final out = Mesh();
    // seed with updated vertex positions later; first pass creates slots
    for (var i = 0; i < m.vertices.length; i++) {
      out.vertices.add(Vec3.zero);
    }

    for (final e in edgeFaces.keys) {
      final adj = edgeFaces[e]!;
      Vec3 ep;
      if (adj.length >= 2) {
        ep = (m.vertices[e.$1] + m.vertices[e.$2] + facePoints[adj[0]] + facePoints[adj[1]]) / 4;
      } else {
        ep = (m.vertices[e.$1] + m.vertices[e.$2]) / 2;
      }
      edgePointIndex[e] = out.vertices.length;
      out.vertices.add(ep);
    }

    // updated vertex positions
    for (var i = 0; i < m.vertices.length; i++) {
      final adjFaces = vertFaces[i] ?? [];
      final adjEdges = vertEdges[i] ?? [];
      final boundaryEdges = adjEdges.where((e) => (edgeFaces[e] ?? []).length < 2).toList();
      final v = m.vertices[i];
      Vec3 nv;
      if (boundaryEdges.length >= 2) {
        // boundary vertex: keep on the boundary curve
        final n1 = boundaryEdges[0].$1 == i ? boundaryEdges[0].$2 : boundaryEdges[0].$1;
        final n2 = boundaryEdges[1].$1 == i ? boundaryEdges[1].$2 : boundaryEdges[1].$1;
        nv = (v * 6 + m.vertices[n1] + m.vertices[n2]) / 8;
      } else if (adjFaces.isEmpty) {
        nv = v; // loose vertex
      } else {
        var fAvg = Vec3.zero;
        for (final fi in adjFaces) {
          fAvg += facePoints[fi];
        }
        fAvg = fAvg / adjFaces.length.toDouble();
        var eAvg = Vec3.zero;
        for (final e in adjEdges) {
          eAvg += (m.vertices[e.$1] + m.vertices[e.$2]) / 2;
        }
        eAvg = eAvg / adjEdges.length.toDouble();
        final n = adjFaces.length.toDouble();
        nv = (fAvg + eAvg * 2 + v * (n - 3)) / n;
      }
      out.vertices[i] = nv;
    }

    // one face point per original face
    final facePointIndex = List<int>.filled(m.faces.length, -1);
    for (var fi = 0; fi < m.faces.length; fi++) {
      facePointIndex[fi] = out.vertices.length;
      out.vertices.add(facePoints[fi]);
    }

    // rebuild faces: corner quad per vertex
    for (var fi = 0; fi < m.faces.length; fi++) {
      final f = m.faces[fi];
      for (var i = 0; i < f.length; i++) {
        final prev = f[(i + f.length - 1) % f.length];
        final cur = f[i];
        final next = f[(i + 1) % f.length];
        final ePrev = prev < cur ? (prev, cur) : (cur, prev);
        final eNext = cur < next ? (cur, next) : (next, cur);
        out.faces.add([cur, edgePointIndex[eNext]!, facePointIndex[fi], edgePointIndex[ePrev]!]);
      }
    }

    // loose edges get a midpoint and split in two
    for (final e in m.edges) {
      final key = e.$1 < e.$2 ? e : (e.$2, e.$1);
      var midIdx = edgePointIndex[key];
      if (midIdx == null) {
        midIdx = out.vertices.length;
        out.vertices.add((m.vertices[e.$1] + m.vertices[e.$2]) / 2);
      }
      out.edges.add((e.$1, midIdx));
      out.edges.add((midIdx, e.$2));
    }
    return out;
  }

  @override
  SubdivisionModifier clone() {
    final m = SubdivisionModifier(levels: levels);
    m.enabled = enabled;
    return m;
  }

  @override
  Map<String, dynamic> toJson() => {'type': type, 'enabled': enabled, 'levels': levels};

  factory SubdivisionModifier.fromJson(Map<String, dynamic> j) {
    final m = SubdivisionModifier(levels: (j['levels'] as num?)?.toInt() ?? 1);
    m.restoreCommon(j);
    return m;
  }
}

/// Chamfers edges by a width. Implemented as a simple per-vertex bevel:
/// vertices get an extra vertex per face corner, connected by quads.
class BevelModifier extends MeshModifier {
  double amount; // 0..0.5 as a fraction toward edge midpoints
  int segments;

  BevelModifier({this.amount = 0.1, this.segments = 1});

  @override
  String get type => 'bevel';

  @override
  Mesh apply(Mesh input) {
    final m = input;
    final t = amount.clamp(0.0, 0.5);
    if (m.faces.isEmpty || t <= 0) return m.clone();

    // corner vertex: original vertex v slid toward neighbor `toward` in face fi
    final corner = <(int, int, int), int>{};
    final out = Mesh();
    int cornerOf(int fi, int v, int toward) => corner.putIfAbsent((fi, v, toward), () {
          out.vertices.add(m.vertices[v].lerp(m.vertices[toward], t));
          return out.vertices.length - 1;
        });

    // shrunk faces
    for (var fi = 0; fi < m.faces.length; fi++) {
      final f = m.faces[fi];
      final nf = <int>[];
      for (var i = 0; i < f.length; i++) {
        final prev = f[(i + f.length - 1) % f.length];
        final cur = f[i];
        final next = f[(i + 1) % f.length];
        nf.add(cornerOf(fi, cur, prev));
        nf.add(cornerOf(fi, cur, next));
      }
      out.faces.add(nf);
    }

    // chamfer strip along each edge
    final edgeFaces = m.edgeFaceMap();
    for (final e in edgeFaces.keys) {
      final adj = edgeFaces[e]!;
      if (adj.length >= 2) {
        out.faces.add([
          cornerOf(adj[0], e.$1, e.$2),
          cornerOf(adj[1], e.$1, e.$2),
          cornerOf(adj[1], e.$2, e.$1),
          cornerOf(adj[0], e.$2, e.$1),
        ]);
      } else {
        final mid = out.vertices.length;
        out.vertices.add((m.vertices[e.$1] + m.vertices[e.$2]) / 2);
        out.faces.add([cornerOf(adj[0], e.$1, e.$2), mid, cornerOf(adj[0], e.$2, e.$1)]);
      }
    }

    // vertex caps: walk the faces around each vertex
    final vertFaces = <int, List<int>>{};
    for (var fi = 0; fi < m.faces.length; fi++) {
      for (final v in m.faces[fi]) {
        vertFaces.putIfAbsent(v, () => []).add(fi);
      }
    }
    for (final entry in vertFaces.entries) {
      final v = entry.key;
      if (entry.value.length < 3) continue;
      final cap = <int>[];
      final start = entry.value.first;
      var cur = start;
      var ok = true;
      final visited = <int>{};
      while (visited.add(cur)) {
        final f = m.faces[cur];
        final i = f.indexOf(v);
        final next = f[(i + 1) % f.length];
        cap.add(cornerOf(cur, v, next));
        final key = v < next ? (v, next) : (next, v);
        final adj = edgeFaces[key]!;
        final nf = adj.firstWhere((x) => x != cur, orElse: () => -1);
        if (nf < 0) {
          ok = false;
          break;
        }
        cur = nf;
      }
      if (ok && cap.length >= 3) out.faces.add(cap);
    }
    out.edges.addAll(List.of(m.edges));
    return out;
  }

  @override
  BevelModifier clone() {
    final m = BevelModifier(amount: amount, segments: segments);
    m.enabled = enabled;
    return m;
  }

  @override
  Map<String, dynamic> toJson() =>
      {'type': type, 'enabled': enabled, 'amount': amount, 'segments': segments};

  factory BevelModifier.fromJson(Map<String, dynamic> j) {
    final m = BevelModifier(
      amount: (j['amount'] as num?)?.toDouble() ?? 0.1,
      segments: (j['segments'] as num?)?.toInt() ?? 1,
    );
    m.restoreCommon(j);
    return m;
  }
}

/// Gives flat faces thickness by extruding along the face normal.
class SolidifyModifier extends MeshModifier {
  double thickness;

  SolidifyModifier({this.thickness = 0.1});

  @override
  String get type => 'solidify';

  @override
  Mesh apply(Mesh input) {
    final out = Mesh(vertices: List.of(input.vertices));
    final n = input.faces.length;
    // duplicate verts offset by -thickness along the face normal for the back faces
    final backIndex = List<int>.filled(input.vertices.length, -1);
    int backVert(int v, Vec3 off) {
      if (backIndex[v] < 0) {
        backIndex[v] = out.vertices.length;
        out.vertices.add(input.vertices[v] + off);
      }
      return backIndex[v];
    }

    final edgeFaces = input.edgeFaceMap();
    for (var fi = 0; fi < n; fi++) {
      final f = input.faces[fi];
      out.faces.add(List.of(f));
      final off = input.faceNormal(fi) * -thickness;
      final back = f.map((v) => backVert(v, off)).toList().reversed.toList();
      out.faces.add(back);
    }
    // walls on boundary edges
    for (final e in edgeFaces.keys) {
      if (edgeFaces[e]!.length == 1) {
        final fi = edgeFaces[e]!.first;
        final off = input.faceNormal(fi) * -thickness;
        final b1 = backVert(e.$1, off);
        final b2 = backVert(e.$2, off);
        // orient the wall so it faces outward
        out.faces.add([e.$2, e.$1, b1, b2]);
      }
    }
    for (final e in input.edges) {
      out.edges.add(e);
    }
    return out;
  }

  @override
  SolidifyModifier clone() {
    final m = SolidifyModifier(thickness: thickness);
    m.enabled = enabled;
    return m;
  }

  @override
  Map<String, dynamic> toJson() => {'type': type, 'enabled': enabled, 'thickness': thickness};

  factory SolidifyModifier.fromJson(Map<String, dynamic> j) {
    final m = SolidifyModifier(thickness: (j['thickness'] as num?)?.toDouble() ?? 0.1);
    m.restoreCommon(j);
    return m;
  }
}
