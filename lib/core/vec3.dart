import 'dart:math' as math;

/// Immutable 3D vector. Z is up, matching Blender conventions.
class Vec3 {
  final double x, y, z;

  const Vec3(this.x, this.y, this.z);

  static const zero = Vec3(0, 0, 0);
  static const unitX = Vec3(1, 0, 0);
  static const unitY = Vec3(0, 1, 0);
  static const unitZ = Vec3(0, 0, 1);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator -() => Vec3(-x, -y, -z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator /(double s) => Vec3(x / s, y / s, z / s);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double get length => math.sqrt(x * x + y * y + z * z);
  double get length2 => x * x + y * y + z * z;

  Vec3 normalized() {
    final l = length;
    return l < 1e-12 ? Vec3.zero : this / l;
  }

  double distanceTo(Vec3 o) => (this - o).length;

  Vec3 lerp(Vec3 o, double t) => this + (o - this) * t;

  Vec3 min(Vec3 o) => Vec3(math.min(x, o.x), math.min(y, o.y), math.min(z, o.z));
  Vec3 max(Vec3 o) => Vec3(math.max(x, o.x), math.max(y, o.y), math.max(z, o.z));

  /// Component-wise multiply.
  Vec3 mulVec(Vec3 o) => Vec3(x * o.x, y * o.y, z * o.z);

  Vec3 withAxis(int axis, double v) =>
      axis == 0 ? Vec3(v, y, z) : axis == 1 ? Vec3(x, v, z) : Vec3(x, y, v);

  double axisValue(int axis) => axis == 0 ? x : axis == 1 ? y : z;

  List<double> toJson() => [x, y, z];

  factory Vec3.fromJson(List<dynamic> j) =>
      Vec3((j[0] as num).toDouble(), (j[1] as num).toDouble(), (j[2] as num).toDouble());

  @override
  bool operator ==(Object other) =>
      other is Vec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Vec3(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}

/// Row-major 4x4 matrix.
class Mat4 {
  /// m[row * 4 + col]
  final List<double> m;

  Mat4(this.m);

  factory Mat4.identity() => Mat4([
        1, 0, 0, 0, //
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
      ]);

  factory Mat4.translation(Vec3 t) => Mat4([
        1, 0, 0, t.x, //
        0, 1, 0, t.y,
        0, 0, 1, t.z,
        0, 0, 0, 1,
      ]);

  factory Mat4.scaling(Vec3 s) => Mat4([
        s.x, 0, 0, 0, //
        0, s.y, 0, 0,
        0, 0, s.z, 0,
        0, 0, 0, 1,
      ]);

  factory Mat4.rotationX(double a) {
    final c = math.cos(a), s = math.sin(a);
    return Mat4([
      1, 0, 0, 0, //
      0, c, -s, 0,
      0, s, c, 0,
      0, 0, 0, 1,
    ]);
  }

  factory Mat4.rotationY(double a) {
    final c = math.cos(a), s = math.sin(a);
    return Mat4([
      c, 0, s, 0, //
      0, 1, 0, 0,
      -s, 0, c, 0,
      0, 0, 0, 1,
    ]);
  }

  factory Mat4.rotationZ(double a) {
    final c = math.cos(a), s = math.sin(a);
    return Mat4([
      c, -s, 0, 0, //
      s, c, 0, 0,
      0, 0, 1, 0,
      0, 0, 0, 1,
    ]);
  }

  /// Rotation of `angle` radians around `axis` (must be normalized).
  factory Mat4.rotationAxis(Vec3 axis, double angle) {
    final c = math.cos(angle), s = math.sin(angle), t = 1 - c;
    final x = axis.x, y = axis.y, z = axis.z;
    return Mat4([
      t * x * x + c, t * x * y - s * z, t * x * z + s * y, 0, //
      t * x * y + s * z, t * y * y + c, t * y * z - s * x, 0,
      t * x * z - s * y, t * y * z + s * x, t * z * z + c, 0,
      0, 0, 0, 1,
    ]);
  }

  factory Mat4.perspective(double fovY, double aspect, double near, double far) {
    final f = 1 / math.tan(fovY / 2);
    return Mat4([
      f / aspect, 0, 0, 0, //
      0, f, 0, 0,
      0, 0, (far + near) / (near - far), 2 * far * near / (near - far),
      0, 0, -1, 0,
    ]);
  }

  /// `height` is the full world-space view height at the target plane.
  factory Mat4.ortho(double height, double aspect, double near, double far) {
    final t = height / 2, r = t * aspect;
    return Mat4([
      1 / r, 0, 0, 0, //
      0, 1 / t, 0, 0,
      0, 0, -2 / (far - near), -(far + near) / (far - near),
      0, 0, 0, 1,
    ]);
  }

  factory Mat4.lookAt(Vec3 eye, Vec3 target, Vec3 up) {
    final f = (target - eye).normalized();
    var r = f.cross(up);
    if (r.length2 < 1e-12) {
      r = f.cross(Vec3.unitY);
    }
    r = r.normalized();
    final u = r.cross(f);
    return Mat4([
      r.x, r.y, r.z, -r.dot(eye), //
      u.x, u.y, u.z, -u.dot(eye),
      -f.x, -f.y, -f.z, f.dot(eye),
      0, 0, 0, 1,
    ]);
  }

  Mat4 operator *(Mat4 o) {
    final r = List<double>.filled(16, 0);
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        var s = 0.0;
        for (var k = 0; k < 4; k++) {
          s += m[i * 4 + k] * o.m[k * 4 + j];
        }
        r[i * 4 + j] = s;
      }
    }
    return Mat4(r);
  }

  /// Transforms a point (w = 1). Returns xyz / w.
  Vec3 transformPoint(Vec3 p) {
    final x = m[0] * p.x + m[1] * p.y + m[2] * p.z + m[3];
    final y = m[4] * p.x + m[5] * p.y + m[6] * p.z + m[7];
    final z = m[8] * p.x + m[9] * p.y + m[10] * p.z + m[11];
    final w = m[12] * p.x + m[13] * p.y + m[14] * p.z + m[15];
    if (w.abs() < 1e-12) return Vec3(x, y, z);
    return Vec3(x / w, y / w, z / w);
  }

  /// Transforms a direction (w = 0), ignoring translation.
  Vec3 transformDir(Vec3 p) => Vec3(
        m[0] * p.x + m[1] * p.y + m[2] * p.z,
        m[4] * p.x + m[5] * p.y + m[6] * p.z,
        m[8] * p.x + m[9] * p.y + m[10] * p.z,
      );

  /// Transforms a point without dividing by w. Useful for raw clip coords.
  List<double> transformRaw(Vec3 p) => [
        m[0] * p.x + m[1] * p.y + m[2] * p.z + m[3],
        m[4] * p.x + m[5] * p.y + m[6] * p.z + m[7],
        m[8] * p.x + m[9] * p.y + m[10] * p.z + m[11],
        m[12] * p.x + m[13] * p.y + m[14] * p.z + m[15],
      ];

  Mat4 transposed() => Mat4(List.generate(16, (i) => m[(i % 4) * 4 + i ~/ 4]));

  /// General 4x4 inverse via adjugate. Returns null if singular.
  Mat4? inverted() {
    final inv = List<double>.filled(16, 0);
    inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
    inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
    inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
    inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
    inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
    inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
    inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
    inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
    inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
    inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
    inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
    inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
    inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
    inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
    inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
    inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];
    final det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
    if (det.abs() < 1e-15) return null;
    for (var i = 0; i < 16; i++) {
      inv[i] /= det;
    }
    return Mat4(inv);
  }
}
