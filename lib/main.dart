import 'package:flutter/material.dart';

import 'app.dart';
import 'app_state.dart';
import 'core/primitives.dart';
import 'core/scene.dart';

void main() {
  // One AppState for the whole app lifetime — resizes never recreate it.
  final state = AppState();
  state.scene.add(SceneObject(name: 'Cube', mesh: Primitives.cube()));
  state.selectObject(0);
  runApp(ToasterApp(state: state));
}
