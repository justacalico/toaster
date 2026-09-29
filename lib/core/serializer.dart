import 'dart:convert';

import 'mesh.dart';
import 'scene.dart';
import 'vec3.dart';

/// Scene serialization: .toast JSON format plus OBJ import/export.
class Serializer {
  Serializer._(); // coverage:ignore-line

  static const fileExtension = 'toast';

  static String encode(Scene scene) =>
      const JsonEncoder.withIndent('  ').convert(scene.toJson());

  static Scene decode(String text) {
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic>) throw const FormatException('not a scene file');
    return Scene.fromJson(j);
  }

  /// Exports evaluated meshes in world space as Wavefront OBJ.
  static String toObj(Scene scene) {
    final b = StringBuffer('# exported from toaster\n');
    var offset = 1;
    for (final o in scene.objects) {
      if (!o.visible) continue;
      b.writeln('o ${o.name}');
      final m = o.evaluatedMesh;
      final mat = o.matrix;
      for (final v in m.vertices) {
        final w = mat.transformPoint(v);
        b.writeln('v ${w.x} ${w.y} ${w.z}');
      }
      for (final f in m.faces) {
        b.writeln('f ${f.map((i) => i + offset).join(' ')}');
      }
      offset += m.vertices.length;
    }
    return b.toString();
  }

  /// Parses OBJ text into a mesh (v/f only, groups merge into one mesh).
  static Mesh fromObj(String text) {
    final mesh = Mesh();
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      switch (parts[0]) {
        case 'v':
          if (parts.length >= 4) {
            mesh.vertices.add(Vec3(
              double.parse(parts[1]),
              double.parse(parts[2]),
              double.parse(parts[3]),
            ));
          }
        case 'f':
          final f = <int>[];
          for (var i = 1; i < parts.length; i++) {
            final tok = parts[i].split('/').first;
            var idx = int.parse(tok);
            if (idx < 0) idx = mesh.vertices.length + idx + 1;
            f.add(idx - 1);
          }
          if (f.length >= 3) mesh.faces.add(f);
      }
    }
    return mesh;
  }
}
