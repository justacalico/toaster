import 'vec3.dart';
import 'scene.dart';

/// Ray vs triangle (Moller-Trumbore). Returns t along the ray or null.
double? rayTriangle(Vec3 ro, Vec3 rd, Vec3 a, Vec3 b, Vec3 c) {
  const eps = 1e-9;
  final e1 = b - a, e2 = c - a;
  final p = rd.cross(e2);
  final det = e1.dot(p);
  if (det.abs() < eps) return null;
  final inv = 1 / det;
  final t = ro - a;
  final u = t.dot(p) * inv;
  if (u < -eps || u > 1 + eps) return null;
  final q = t.cross(e1);
  final v = rd.dot(q) * inv;
  if (v < -eps || u + v > 1 + eps) return null;
  final tt = e2.dot(q) * inv;
  return tt > eps ? tt : null;
}

/// Closest hit of a ray against an object's evaluated mesh in world space.
/// Returns (t, faceIndex).
(double, int)? rayMesh(Vec3 ro, Vec3 rd, SceneObject obj) {
  final inv = obj.inverseMatrix;
  final lro = inv.transformPoint(ro);
  final lrd = inv.transformDir(rd);
  final m = obj.evaluatedMesh;
  double? best;
  var bestFace = -1;
  for (final (fi, tri) in m.triangulated()) {
    final t = rayTriangle(lro, lrd, m.vertices[tri[0]], m.vertices[tri[1]], m.vertices[tri[2]]);
    if (t != null && (best == null || t < best)) {
      best = t;
      bestFace = fi;
    }
  }
  return best == null ? null : (best, bestFace);
}

/// Picks the frontmost object under a ray. Returns (objectIndex, depth).
(int, double)? pickObject(Vec3 ro, Vec3 rd, Scene scene, {bool Function(int)? filter}) {
  int? best;
  var bestT = double.infinity;
  for (var i = 0; i < scene.objects.length; i++) {
    final o = scene.objects[i];
    if (!o.visible) continue;
    if (filter != null && !filter(i)) continue;
    final hit = rayMesh(ro, rd, o);
    if (hit != null && hit.$1 < bestT) {
      bestT = hit.$1;
      best = i;
    }
  }
  return best == null ? null : (best, bestT);
}

/// Distance from a point to a segment.
double pointSegmentDist(double px, double py, double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay;
  final l2 = dx * dx + dy * dy;
  var t = l2 < 1e-12 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / l2;
  t = t.clamp(0.0, 1.0);
  final cx = ax + dx * t, cy = ay + dy * t;
  final ddx = px - cx, ddy = py - cy;
  return ddx * ddx + ddy * ddy; // squared
}
