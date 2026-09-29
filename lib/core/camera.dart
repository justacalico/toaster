import 'dart:math' as math;

import 'vec3.dart';

/// Orbit camera, Blender-style: yaw/pitch around a target point,
/// perspective or orthographic projection. Z is up.
class OrbitCamera {
  Vec3 target;
  double distance;
  double yaw; // radians around Z, 0 = camera on +X looking -X
  double pitch; // radians above the XY plane
  double fovY;
  bool perspective;
  double orthoHeight; // world-space view height in ortho mode
  double near, far;

  OrbitCamera({
    this.target = Vec3.zero,
    this.distance = 10,
    this.yaw = -math.pi / 4,
    this.pitch = math.pi / 6,
    this.fovY = math.pi / 3,
    this.perspective = true,
    this.orthoHeight = 6,
    this.near = 0.05,
    this.far = 1000,
  });

  Vec3 get eye {
    final cp = math.cos(pitch);
    return target +
        Vec3(math.cos(yaw) * cp, math.sin(yaw) * cp, math.sin(pitch)) * distance;
  }

  Vec3 get forward => (target - eye).normalized();

  Vec3 get right {
    var r = forward.cross(Vec3.unitZ);
    if (r.length2 < 1e-12) r = forward.cross(Vec3.unitY);
    return r.normalized();
  }

  Vec3 get screenUp => right.cross(forward).normalized();

  Mat4 get view => Mat4.lookAt(eye, target, _upHint());

  Vec3 _upHint() => pitch.abs() > math.pi / 2 - 0.01 ? Vec3.unitY : Vec3.unitZ;

  void orbit(double dYaw, double dPitch) {
    yaw -= dYaw;
    pitch = (pitch + dPitch).clamp(-math.pi / 2 + 0.001, math.pi / 2 - 0.001);
  }

  void pan(double dx, double dy, double viewportHeight) {
    final wpp = _worldPerPixel(viewportHeight);
    target += right * (-dx * wpp) + screenUp * (dy * wpp);
  }

  void zoom(double factor) {
    if (perspective) {
      distance = (distance * factor).clamp(0.1, 500);
    } else {
      orthoHeight = (orthoHeight * factor).clamp(0.05, 500);
    }
  }

  double _worldPerPixel(double viewportHeight) {
    if (!perspective) return orthoHeight / viewportHeight;
    final depth = distance;
    return 2 * depth * math.tan(fovY / 2) / viewportHeight;
  }

  /// World-space delta for a screen-space pixel delta measured at the
  /// given distance from the camera.
  Vec3 screenDeltaToWorld(double dx, double dy, double viewportHeight, double depth) {
    final wpp = perspective
        ? 2 * depth * math.tan(fovY / 2) / viewportHeight
        : orthoHeight / viewportHeight;
    return right * (dx * wpp) + screenUp * (-dy * wpp);
  }

  /// Projects a world point. Returns (x, y, viewDepth) or null behind camera.
  (double, double, double)? project(Vec3 p, double width, double height) {
    final vp = view.transformPoint(p);
    final depth = -vp.z;
    if (depth < near) return null;
    double nx, ny;
    if (perspective) {
      final halfH = depth * math.tan(fovY / 2);
      final halfW = halfH * (width / height);
      nx = vp.x / halfW;
      ny = vp.y / halfH;
    } else {
      nx = vp.x / (orthoHeight * width / height / 2);
      ny = vp.y / (orthoHeight / 2);
    }
    return ((nx + 1) * 0.5 * width, (1 - ny) * 0.5 * height, depth);
  }

  /// A picking ray through a screen point.
  (Vec3 origin, Vec3 dir) ray(double x, double y, double width, double height) {
    final nx = x / width * 2 - 1;
    final ny = 1 - y / height * 2;
    if (perspective) {
      final t = math.tan(fovY / 2);
      final dir = (forward + right * (nx * t * width / height) + screenUp * (ny * t)).normalized();
      return (eye, dir);
    }
    final origin = eye + right * (nx * orthoHeight * width / height / 2) + screenUp * (ny * orthoHeight / 2);
    return (origin, forward);
  }

  void setView(String preset) {
    const d = 10.0;
    switch (preset) {
      case 'front':
        yaw = -math.pi / 2;
        pitch = 0;
      case 'back':
        yaw = math.pi / 2;
        pitch = 0;
      case 'right':
        yaw = 0;
        pitch = 0;
      case 'left':
        yaw = math.pi;
        pitch = 0;
      case 'top':
        yaw = -math.pi / 2;
        pitch = math.pi / 2 - 0.001;
      case 'bottom':
        yaw = -math.pi / 2;
        pitch = -math.pi / 2 + 0.001;
      default:
        yaw = -math.pi / 4;
        pitch = math.pi / 6;
        distance = d;
        target = Vec3.zero;
    }
  }

  void togglePerspective() {
    if (perspective) {
      orthoHeight = 2 * distance * math.tan(fovY / 2) * 0.55;
    }
    perspective = !perspective;
  }

  /// Frames the given bounds: moves the target and picks a distance.
  void frame(Vec3 lo, Vec3 hi, double viewportAspect) {
    target = (lo + hi) / 2;
    final r = (hi - lo).length / 2;
    if (r < 1e-6) {
      distance = 3;
      orthoHeight = 2;
      return;
    }
    distance = (r / math.tan(fovY / 2) / math.min(viewportAspect, 1.0)) * 1.15;
    orthoHeight = r * 2.3;
  }

  OrbitCamera clone() => OrbitCamera(
        target: target,
        distance: distance,
        yaw: yaw,
        pitch: pitch,
        fovY: fovY,
        perspective: perspective,
        orthoHeight: orthoHeight,
        near: near,
        far: far,
      );
}
