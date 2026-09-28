import 'dart:ui';

import 'mesh.dart';
import 'modifiers.dart';
import 'vec3.dart';

/// Simple viewport material.
class ShadeMaterial {
  Color color;
  double metallic;
  double roughness;
  bool useNodes; // reserved for future node editor

  ShadeMaterial({
    this.color = const Color(0xFF8C97A3),
    this.metallic = 0,
    this.roughness = 0.5,
    this.useNodes = false,
  });

  ShadeMaterial clone() => ShadeMaterial(
        color: color,
        metallic: metallic,
        roughness: roughness,
        useNodes: useNodes,
      );

  Map<String, dynamic> toJson() => {
        'color': color.toARGB32(),
        'metallic': metallic,
        'roughness': roughness,
        'useNodes': useNodes,
      };

  factory ShadeMaterial.fromJson(Map<String, dynamic> j) => ShadeMaterial(
        color: Color((j['color'] as num).toInt()),
        metallic: (j['metallic'] as num?)?.toDouble() ?? 0,
        roughness: (j['roughness'] as num?)?.toDouble() ?? 0.5,
        useNodes: j['useNodes'] as bool? ?? false,
      );
}

/// One object in the scene: a mesh plus transform, material and modifiers.
class SceneObject {
  String name;
  Mesh mesh;
  Vec3 location;
  Vec3 rotation; // euler radians, XYZ order
  Vec3 scale;
  ShadeMaterial material;
  final List<MeshModifier> modifiers;
  bool visible;
  bool smoothShading;
  bool selectedInOutliner;

  SceneObject({
    required this.name,
    required this.mesh,
    Vec3? location,
    Vec3? rotation,
    Vec3? scale,
    ShadeMaterial? material,
    List<MeshModifier>? modifiers,
    this.visible = true,
    this.smoothShading = false,
    this.selectedInOutliner = false,
  })  : location = location ?? Vec3.zero,
        rotation = rotation ?? Vec3.zero,
        scale = scale ?? const Vec3(1, 1, 1),
        material = material ?? ShadeMaterial(),
        modifiers = modifiers ?? [];

  /// Local -> world transform.
  Mat4 get matrix {
    var m = Mat4.translation(location);
    m = m * Mat4.rotationZ(rotation.z) * Mat4.rotationY(rotation.y) * Mat4.rotationX(rotation.x);
    return m * Mat4.scaling(scale);
  }

  /// World -> local transform (inverse of [matrix]).
  Mat4 get inverseMatrix {
    final invS = Mat4.scaling(Vec3(
      scale.x == 0 ? 1 : 1 / scale.x,
      scale.y == 0 ? 1 : 1 / scale.y,
      scale.z == 0 ? 1 : 1 / scale.z,
    ));
    final invR = Mat4.rotationX(-rotation.x) * Mat4.rotationY(-rotation.y) * Mat4.rotationZ(-rotation.z);
    return invS * invR * Mat4.translation(-location);
  }

  /// Mesh with modifiers applied, in local space.
  Mesh get evaluatedMesh {
    var m = mesh;
    for (final mod in modifiers) {
      if (mod.enabled) m = mod.apply(m);
    }
    return m;
  }

  Vec3 get worldCenter => matrix.transformPoint(mesh.centroid);

  SceneObject clone() => SceneObject(
        name: name,
        mesh: mesh.clone(),
        location: location,
        rotation: rotation,
        scale: scale,
        material: material.clone(),
        modifiers: modifiers.map((m) => m.clone()).toList(),
        visible: visible,
        smoothShading: smoothShading,
        selectedInOutliner: selectedInOutliner,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'location': location.toJson(),
        'rotation': rotation.toJson(),
        'scale': scale.toJson(),
        'material': material.toJson(),
        'visible': visible,
        'smoothShading': smoothShading,
        'vertices': mesh.vertices.map((v) => v.toJson()).toList(),
        'faces': mesh.faces,
        'edges': mesh.edges.map((e) => [e.$1, e.$2]).toList(),
        'modifiers': modifiers.map((m) => m.toJson()).toList(),
      };

  factory SceneObject.fromJson(Map<String, dynamic> j) => SceneObject(
        name: j['name'] as String,
        mesh: Mesh(
          vertices: (j['vertices'] as List).map((v) => Vec3.fromJson(v as List)).toList(),
          faces: (j['faces'] as List).map((f) => (f as List).map((i) => (i as num).toInt()).toList()).toList(),
          edges: (j['edges'] as List?)
                  ?.map((e) => ((e as List)[0] as num).toInt() >= ((e)[1] as num).toInt()
                      ? ((e[1] as num).toInt(), (e[0] as num).toInt())
                      : ((e[0] as num).toInt(), (e[1] as num).toInt()))
                  .toList() ??
              [],
        ),
        location: Vec3.fromJson(j['location'] as List),
        rotation: Vec3.fromJson(j['rotation'] as List),
        scale: Vec3.fromJson(j['scale'] as List),
        material: ShadeMaterial.fromJson(j['material'] as Map<String, dynamic>),
        visible: j['visible'] as bool? ?? true,
        smoothShading: j['smoothShading'] as bool? ?? false,
        modifiers: (j['modifiers'] as List?)
                ?.map((m) => MeshModifier.fromJson(m as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

/// The whole scene.
class Scene {
  final List<SceneObject> objects;
  Color backgroundColor;
  Color gridColor;
  bool showGrid;
  bool showAxes;

  Scene({
    List<SceneObject>? objects,
    this.backgroundColor = const Color(0xFF1E1E22),
    this.gridColor = const Color(0xFF3A3A40),
    this.showGrid = true,
    this.showAxes = true,
  }) : objects = objects ?? [];

  Scene clone() => Scene(
        objects: objects.map((o) => o.clone()).toList(),
        backgroundColor: backgroundColor,
        gridColor: gridColor,
        showGrid: showGrid,
        showAxes: showAxes,
      );

  int add(SceneObject o) {
    objects.add(o);
    return objects.length - 1;
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'backgroundColor': backgroundColor.toARGB32(),
        'gridColor': gridColor.toARGB32(),
        'showGrid': showGrid,
        'showAxes': showAxes,
        'objects': objects.map((o) => o.toJson()).toList(),
      };

  factory Scene.fromJson(Map<String, dynamic> j) => Scene(
        objects: (j['objects'] as List?)
                ?.map((o) => SceneObject.fromJson(o as Map<String, dynamic>))
                .toList() ??
            [],
        backgroundColor: Color((j['backgroundColor'] as num?)?.toInt() ?? 0xFF1E1E22),
        gridColor: Color((j['gridColor'] as num?)?.toInt() ?? 0xFF3A3A40),
        showGrid: j['showGrid'] as bool? ?? true,
        showAxes: j['showAxes'] as bool? ?? true,
      );
}
