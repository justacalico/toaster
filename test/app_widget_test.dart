import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toaster/app.dart';
import 'package:toaster/app_state.dart';
import 'package:toaster/core/renderer.dart';
import 'package:toaster/core/primitives.dart';
import 'package:toaster/core/scene.dart';
import 'package:toaster/core/file_store.dart';
import 'package:toaster/ui/dialogs.dart';
import 'package:toaster/ui/panels.dart';
import 'package:toaster/ui/viewport.dart';
import 'package:toaster/ui/viewport_painter.dart';

AppState freshState() {
  final s = AppState();
  s.scene.add(SceneObject(name: 'Cube', mesh: Primitives.cube()));
  s.selectObject(0);
  return s;
}

Future<AppState> pumpApp(WidgetTester tester, {Size size = const Size(1200, 900), AppState? state}) {
  final s = state ?? freshState();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  return tester.pumpWidget(ToasterApp(state: s)).then((_) => s);
}

Future<void> openMenu(WidgetTester tester, String menu) async {
  await tester.tap(find.text(menu).first);
  await tester.pumpAndSettle();
}

Future<void> tapMenuItem(WidgetTester tester, String item) async {
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

/// Bounded settle for dialogs: TextField cursor blink means pumpAndSettle
/// would hang forever.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

String? _clipData;

void main() {
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        _clipData = call.arguments['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') return {'text': _clipData ?? ''};
      return null;
    });
  });

  testWidgets('app boots wide and renders chrome', (tester) async {
    await pumpApp(tester);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Outliner'), findsOneWidget);
    expect(find.text('Edit Mode'), findsNothing);
    expect(find.text('Object Mode'), findsWidgets); // status + HUD + mode chip
    await expectLater(find.byType(ToasterApp), matchesGoldenFile('goldens/app_wide.png'));
  });

  testWidgets('compact layout shows bottom tool row', (tester) async {
    final s = await pumpApp(tester, size: const Size(420, 800));
    expect(find.text('File'), findsOneWidget);
    // panels button exists in compact mode
    expect(find.byTooltip('Panels'), findsOneWidget);
    await tester.tap(find.byTooltip('Panels'));
    await settle(tester);
    expect(find.text('Outliner'), findsOneWidget);
    Navigator.pop(tester.element(find.byType(BottomSheet)));
    await tester.pumpAndSettle();
    s;
  });

  testWidgets('menus: Add primitives via menu', (tester) async {
    final s = await pumpApp(tester);
    await openMenu(tester, 'Add');
    await tapMenuItem(tester, 'Torus');
    expect(s.scene.objects.any((o) => o.name == 'Torus'), isTrue);
    await openMenu(tester, 'Add');
    await tapMenuItem(tester, 'Monkey');
    expect(s.scene.objects.any((o) => o.name == 'Monkey'), isTrue);
  });

  testWidgets('menus: Edit ops', (tester) async {
    final s = await pumpApp(tester);
    await openMenu(tester, 'Edit');
    await tapMenuItem(tester, 'Duplicate');
    expect(s.scene.objects.length, 2);
    s.selectAll(); // join needs the pair selected
    await openMenu(tester, 'Edit');
    await tapMenuItem(tester, 'Join');
    expect(s.scene.objects.length, 1);
    await openMenu(tester, 'Edit');
    await tapMenuItem(tester, 'Delete');
    expect(s.scene.objects, isEmpty);
    await openMenu(tester, 'Edit');
    await tapMenuItem(tester, 'Undo');
    expect(s.scene.objects.length, 1);
    await openMenu(tester, 'Edit');
    await tapMenuItem(tester, 'Redo');
    expect(s.scene.objects, isEmpty);
  });

  testWidgets('menus: Mesh ops route to state', (tester) async {
    final s = await pumpApp(tester);
    s.enterEditMode();
    await tester.pumpWidget(ToasterApp(state: s));
    for (final item in ['Extrude', 'Inset', 'Subdivide', 'Fill', 'Merge by Distance', 'Flip Normals', 'Shade Smooth / Flat']) {
      await openMenu(tester, 'Mesh');
      // some ops mutate selection; reset to a known face selection
      s.selFaces = {1};
      s.selMode = SelMode.face;
      await tapMenuItem(tester, item);
    }
    expect(s.editObj!.mesh.faces.length, greaterThan(6));
  });

  testWidgets('menus: View presets and toggles', (tester) async {
    final s = await pumpApp(tester);
    for (final v in ['Front', 'Right', 'Top', 'Bottom']) {
      await openMenu(tester, 'View');
      await tapMenuItem(tester, v);
    }
    expect(s.camera.pitch, lessThan(0)); // bottom
    await openMenu(tester, 'View');
    await tapMenuItem(tester, 'Toggle Perspective/Ortho');
    expect(s.camera.perspective, isFalse);
    await openMenu(tester, 'View');
    await tapMenuItem(tester, 'Frame Selected');
    await openMenu(tester, 'View');
    await tapMenuItem(tester, 'Grid');
    expect(s.scene.showGrid, isFalse);
    await openMenu(tester, 'View');
    await tapMenuItem(tester, 'Overlays');
    expect(s.showOverlays, isFalse);
  });

  testWidgets('menus: File new', (tester) async {
    final s = await pumpApp(tester);
    await openMenu(tester, 'File');
    await tapMenuItem(tester, 'New');
    expect(s.scene.objects, isEmpty);
  });

  testWidgets('menus: Help about', (tester) async {
    await pumpApp(tester);
    await openMenu(tester, 'Help');
    await tapMenuItem(tester, 'About toaster');
    expect(find.text('toaster'), findsWidgets);
    Navigator.pop(tester.element(find.byType(AlertDialog)));
    await tester.pumpAndSettle();
  });

  testWidgets('mode switcher and sel mode chips', (tester) async {
    final s = await pumpApp(tester);
    await tester.tap(find.text('Edit').last);
    await tester.pump();
    expect(s.mode, EditorMode.edit);
    // sel mode chips appear
    for (final (chip, mode) in [('V', SelMode.vertex), ('E', SelMode.edge), ('F', SelMode.face)]) {
      await tester.tap(find.text(chip).first);
      await tester.pump();
      expect(s.selMode, mode);
    }
    await tester.tap(find.text('Object').last);
    await tester.pump();
    expect(s.mode, EditorMode.object);
  });

  testWidgets('shading switcher', (tester) async {
    final s = await pumpApp(tester);
    final icons = [Icons.grid_3x3, Icons.circle, Icons.circle_outlined];
    for (final icon in icons) {
      await tester.tap(find.byIcon(icon).first);
      await tester.pump();
    }
    expect(s.shading, ShadingMode.materialPreview);
  });

  testWidgets('snap toggle chip', (tester) async {
    final s = await pumpApp(tester);
    await tester.tap(find.text('Snap'));
    expect(s.snapEnabled, isTrue);
  });

  testWidgets('toolbar tools and edit extras', (tester) async {
    final s = await pumpApp(tester);
    for (final label in ['Select', 'Move (G)', 'Rotate (R)', 'Scale (S)']) {
      await tester.tap(find.byTooltip(label));
      await tester.pump();
    }
    expect(s.tool, Tool.scale);
    s.enterEditMode();
    await tester.pumpWidget(ToasterApp(state: s));
    await tester.pump();
    for (final tip in ['Extrude (E)', 'Inset (I)', 'Subdivide', 'Fill (F)']) {
      s.selFaces = {1};
      s.selMode = SelMode.face;
      await tester.tap(find.byTooltip(tip));
      await tester.pump();
      s.cancelTransform();
    }
    expect(s.editObj!.mesh.faces.length, greaterThan(6));
  });

  testWidgets('outliner: select, visibility, icons', (tester) async {
    final s = await pumpApp(tester);
    s.addPrimitive('Torus');
    s.addPrimitive('UV Sphere');
    s.addPrimitive('Plane');
    s.addPrimitive('Cylinder');
    s.addPrimitive('Monkey');
    s.addMeshObject('Wire', Primitives.cube()..faces.clear());
    await tester.pumpWidget(ToasterApp(state: s));
    await tester.pump();
    // tap rows (uses various iconFor branches)
    await tester.tap(find.text('Torus'));
    expect(s.activeObj!.name, 'Torus');
    await tester.longPress(find.text('Plane'));
    expect(s.selectedObjects.length, greaterThan(1));
    // visibility toggle on first row icon button
    await tester.tap(find.byIcon(Icons.visibility_outlined).first);
    await tester.pump();
    expect(s.scene.objects.any((o) => !o.visible), isTrue);
    await tester.tap(find.byIcon(Icons.visibility_off_outlined).first);
    await tester.pump();
  });

  testWidgets('outliner empty state', (tester) async {
    await pumpApp(tester, state: AppState());
    expect(find.textContaining('Empty scene'), findsOneWidget);
  });

  testWidgets('properties: item tab edits transform', (tester) async {
    final s = await pumpApp(tester);
    await tester.tap(find.text('Item'));
    await tester.pump();
    // name field
    await tester.enterText(find.byType(TextField).first, 'Renamed');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(s.activeObj!.name, 'Renamed');
    // numeric fields: find by key name 'Location-0-...'
    final numField = find.byKey(ValueKey('Location-0-${s.activeObj!.location.x}'));
    await tester.enterText(numField, '3.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(s.activeObj!.location.x, 3.5);
    // invalid input ignored
    await tester.enterText(find.byKey(ValueKey('Location-0-3.5')), 'abc');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(s.activeObj!.location.x, 3.5);
    // rotation field
    await tester.enterText(find.byKey(const ValueKey('Rotation-1-0.0')), '90');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(s.activeObj!.rotation.y, closeTo(3.14159 / 2, 1e-3));
    // tap outside unfocuses: focus a field then click the outliner
    final field = find.descendant(
        of: find.byKey(const ValueKey('Scale-0-1.0')), matching: find.byType(TextField));
    if (field.evaluate().isNotEmpty) {
      await tester.tap(field);
      await tester.pump();
      await tester.tap(find.text('Outliner'), warnIfMissed: false);
      await tester.pump();
    }
    // shade smooth button
    await tester.tap(find.text('Shade Smooth'));
    await tester.pump();
    expect(s.activeObj!.smoothShading, isTrue);
  });

  testWidgets('properties: material tab swatch and sliders', (tester) async {
    final s = await pumpApp(tester);
    await tester.tap(find.text('Material'));
    await tester.pump();
    // tap a swatch by key
    await tester.tap(find.byKey(const ValueKey('swatch-1')));
    await tester.pump();
    expect(s.activeObj!.material.color.toARGB32(), 0xFFB3402E);
    // sliders
    await tester.drag(find.byType(Slider).first, const Offset(50, 0));
    await tester.pump();
    expect(s.activeObj!.material.metallic, isNot(0));
    await tester.drag(find.byType(Slider).last, const Offset(-50, 0));
    await tester.pump();
  });

  testWidgets('properties: modifiers lifecycle', (tester) async {
    final s = await pumpApp(tester, size: const Size(1400, 1400));
    await tester.tap(find.text('Modifiers'));
    await tester.pump();
    expect(find.textContaining('No modifiers'), findsOneWidget);
    await tester.tap(find.text('Add Modifier'));
    await settle(tester);
    await tester.tap(find.text('Mirror'));
    await tester.pumpAndSettle();
    expect(s.activeObj!.modifiers.length, 1);
    // settings chips inside modifier card
    await tester.tap(find.text('Y'));
    await tester.pump();
    // add subdivision + array for move/apply coverage
    await tester.tap(find.text('Add Modifier'));
    await settle(tester);
    await tester.tap(find.text('Subdivision Surface'));
    await settle(tester);
    await tester.tap(find.text('Add Modifier'));
    await settle(tester);
    await tester.tap(find.text('Array'));
    await settle(tester);
    await tester.tap(find.text('Add Modifier'));
    await settle(tester);
    await tester.tap(find.text('Bevel'));
    await settle(tester);
    await tester.tap(find.text('Add Modifier'));
    await settle(tester);
    await tester.tap(find.text('Solidify'));
    await settle(tester);
    expect(s.activeObj!.modifiers.length, 5);

    final panelScroll = find.descendant(
        of: find.byType(PropertiesPanel), matching: find.byType(Scrollable)).last;
    Future<void> reveal(Finder target) async {
      var guard = 0;
      while (target.evaluate().isEmpty && guard++ < 12) {
        await tester.drag(panelScroll, const Offset(0, -240));
        await tester.pump();
      }
    }

    // merge chip + axis chips on mirror card
    for (final chip in ['Merge', 'X', 'Z', 'Merge']) {
      await reveal(find.text(chip));
      if (find.text(chip).evaluate().isEmpty) continue;
      await tester.scrollUntilVisible(find.text(chip).first, 40, scrollable: panelScroll);
      await tester.pump();
      await tester.tap(find.text(chip).first, warnIfMissed: false);
      await tester.pump();
    }

    // drag every slider in the modifier cards (levels, count, amount, thickness)
    for (var i = 0; i < 4; i++) {
      var guard = 0;
      while (find.byType(Slider).evaluate().length <= i && guard++ < 12) {
        await tester.drag(panelScroll, const Offset(0, -240));
        await tester.pump();
      }
      if (find.byType(Slider).evaluate().length <= i) break;
      await tester.scrollUntilVisible(find.byType(Slider).at(i), 40,
          scrollable: panelScroll);
      await tester.pump();
      await tester.drag(find.byType(Slider).at(i), const Offset(30, 0));
      await tester.pump();
    }

    // toggle enable checkbox
    await reveal(find.byType(Checkbox));
    await tester.scrollUntilVisible(find.byType(Checkbox).first, 40,
        scrollable: panelScroll);
    await tester.pump();
    await tester.tap(find.byType(Checkbox).first, warnIfMissed: false);
    await tester.pump();

    // move/apply/delete icon buttons
    for (final icon in [Icons.arrow_upward, Icons.check, Icons.close]) {
      await reveal(find.byIcon(icon));
      if (find.byIcon(icon).evaluate().isEmpty) continue;
      await tester.tap(find.byIcon(icon).first, warnIfMissed: false);
      await tester.pump();
    }
    // apply all remaining
    await reveal(find.text('Apply All'));
    if (find.text('Apply All').evaluate().isNotEmpty) {
      await tester.tap(find.text('Apply All'), warnIfMissed: false);
      await tester.pump();
    }
  });

  testWidgets('viewport: click selects, MMB orbits, wheel zooms', (tester) async {
    final s = await pumpApp(tester);
    final vp = find.byType(EditorViewport);
    expect(vp, findsOneWidget);
    final center = tester.getCenter(vp);

    // LMB click select
    await tester.tapAt(center);
    await tester.pump();
    expect(s.selectedObjects, {0});

    // MMB drag orbits
    final yawBefore = s.camera.yaw;
    final p = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(p.hover(center));
    await tester.sendEventToBinding(p.down(center, buttons: kMiddleMouseButton));
    await tester.sendEventToBinding(p.move(center + const Offset(60, 20), buttons: kMiddleMouseButton));
    await tester.sendEventToBinding(p.up());
    await tester.pump();
    expect(s.camera.yaw, isNot(yawBefore));

    // shift+MMB pans
    final targetBefore = s.camera.target;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendEventToBinding(p.down(center, buttons: kMiddleMouseButton));
    await tester.sendEventToBinding(p.move(center + const Offset(30, 0), buttons: kMiddleMouseButton));
    await tester.sendEventToBinding(p.up());
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(s.camera.target.distanceTo(targetBefore), greaterThan(0));

    // wheel zoom
    final dBefore = s.camera.distance;
    await tester.sendEventToBinding(p.hover(center));
    await tester.sendEventToBinding(PointerScrollEvent(position: center, scrollDelta: const Offset(0, -120)));
    await tester.pump();
    expect(s.camera.distance, lessThan(dBefore));

    // alt+LMB orbit fallback
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendEventToBinding(p.down(center + const Offset(0, 40), buttons: kPrimaryButton));
    await tester.sendEventToBinding(p.move(center + const Offset(0, 80), buttons: kPrimaryButton));
    await tester.sendEventToBinding(p.up());
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
  });

  testWidgets('viewport: gizmo drag moves object', (tester) async {
    final s = await pumpApp(tester);
    s.setTool(Tool.move);
    await tester.pumpWidget(ToasterApp(state: s));
    await tester.pump();
    final vp = find.byType(EditorViewport);
    final size = tester.getSize(vp);
    final segs = gizmoSegments(s, size);
    expect(segs, isNotEmpty);
    final origin = tester.getTopLeft(vp);
    final tip = origin + segs.first.$3;
    final p = TestPointer(1, PointerDeviceKind.mouse);
    // hover to cover hover-highlight path
    await tester.sendEventToBinding(p.hover(tip));
    await tester.pump();
    await tester.sendEventToBinding(p.down(tip, buttons: kPrimaryButton));
    await tester.sendEventToBinding(p.move(tip + const Offset(40, 0), buttons: kPrimaryButton));
    await tester.sendEventToBinding(p.up());
    await tester.pump();
    expect(s.scene.objects[0].location.length, greaterThan(0));
    // hover away clears highlight
    await tester.sendEventToBinding(p.hover(tester.getTopLeft(vp) + const Offset(5, 5)));
    await tester.pump();
  });

  testWidgets('viewport: rotate tool rings + select-tool click path', (tester) async {
    final s = await pumpApp(tester);
    s.setTool(Tool.rotate);
    await tester.pumpWidget(ToasterApp(state: s));
    await tester.pump();
    final vp = find.byType(EditorViewport);
    final size = tester.getSize(vp);
    expect(gizmoSegments(s, size), isNotEmpty);
    final origin = tester.getTopLeft(vp);
    final p = TestPointer(1, PointerDeviceKind.mouse);
    // drag on the x-axis segment tip -> rotate session
    final tip = origin + gizmoSegments(s, size).first.$3;
    await tester.sendEventToBinding(p.down(tip, buttons: kPrimaryButton));
    await tester.sendEventToBinding(p.move(tip + const Offset(30, 10), buttons: kPrimaryButton));
    await tester.sendEventToBinding(p.up());
    await tester.pump();
    expect(s.scene.objects[0].rotation.length, greaterThan(0));
  });

  testWidgets('viewport: hotkeys drive transform session', (tester) async {
    final s = await pumpApp(tester);
    final vp = find.byType(EditorViewport);
    final center = tester.getCenter(vp);
    final p = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(p.hover(center));
    await tester.pump();

    // G + move + X + Enter
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendEventToBinding(p.hover(center + const Offset(50, 0)));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(s.transform, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(s.transform, isNull);
    expect(s.scene.objects[0].location.x, isNot(0));

    // R + escape cancel
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendEventToBinding(p.hover(center + const Offset(30, 0)));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(s.transform, isNull);

    // S + cancel via RMB
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    final p2 = TestPointer(2, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(p2.down(center, buttons: kSecondaryMouseButton));
    await tester.pump();
    expect(s.transform, isNull);
  });

  testWidgets('viewport: edit-mode hotkeys and select all', (tester) async {
    final s = await pumpApp(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(s.mode, EditorMode.edit);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    expect(s.selMode, SelMode.vertex);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    expect(s.selMode, SelMode.edge);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    expect(s.selMode, SelMode.face);
    // deselect all then ops
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); // deselect
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(s.selectionCount, greaterThan(0));
    s.selFaces = {1};
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    s.selVerts = {0, 1, 2, 3};
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
  });

  testWidgets('viewport: global hotkeys', (tester) async {
    final s = await pumpApp(tester);
    // E outside edit mode = ignored
    Future<void> withCtrl(LogicalKeyboardKey k) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(k);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    // E outside edit mode = ignored
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    // shift+D duplicate
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(s.scene.objects.length, 2);
    // ctrl+J join (select both objects first)
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await withCtrl(LogicalKeyboardKey.keyJ);
    expect(s.scene.objects.length, 1);
    // ctrl+N new scene
    await withCtrl(LogicalKeyboardKey.keyN);
    expect(s.scene.objects, isEmpty);
    // ctrl+Z undo -> back to the joined single object
    await withCtrl(LogicalKeyboardKey.keyZ);
    expect(s.scene.objects.length, 1);
    // ctrl+shift+Z redo -> empty scene again
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(s.scene.objects, isEmpty);
    // ctrl+Y redo -> nothing left to redo
    await withCtrl(LogicalKeyboardKey.keyY);
    expect(s.scene.objects, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ); // shading cycle (no ctrl)
    await tester.pump();
    expect(s.shading, isNot(ShadingMode.solid));
    // views
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    expect(s.camera.perspective, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad5);
    await tester.pump();
    expect(s.camera.perspective, isTrue);
  });

  testWidgets('viewport: scale gizmo drag scales object', (tester) async {
    final s = await pumpApp(tester);
    s.setTool(Tool.scale);
    await tester.pumpWidget(ToasterApp(state: s));
    await tester.pump();
    final vp = find.byType(EditorViewport);
    final size = tester.getSize(vp);
    final segs = gizmoSegments(s, size);
    final origin = tester.getTopLeft(vp);
    final tip = origin + segs.first.$3;
    final p = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(p.down(tip, buttons: kPrimaryButton));
    await tester.sendEventToBinding(p.move(tip + const Offset(50, 0), buttons: kPrimaryButton));
    await tester.sendEventToBinding(p.up());
    await tester.pump();
    expect(s.scene.objects[0].scale.x, greaterThan(1));
  });

  testWidgets('viewport: LMB confirms an active transform', (tester) async {
    final s = await pumpApp(tester);
    final vp = find.byType(EditorViewport);
    final center = tester.getCenter(vp);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(s.transform, isNotNull);
    final p = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(p.hover(center));
    await tester.sendEventToBinding(p.hover(center + const Offset(30, 0)));
    await tester.sendEventToBinding(p.down(center, buttons: kPrimaryButton));
    await tester.pump();
    expect(s.transform, isNull);
    expect(s.scene.objects[0].location.length, greaterThan(0));
    await tester.sendEventToBinding(p.up());
  });

  testWidgets('viewport: pointer released mid-session does not pick', (tester) async {
    final s = await pumpApp(tester);
    final vp = find.byType(EditorViewport);
    final center = tester.getCenter(vp);
    final p = TestPointer(1, PointerDeviceKind.mouse);
    // LMB down BEFORE the session starts, release while it runs
    await tester.sendEventToBinding(p.down(center, buttons: kPrimaryButton));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(s.transform, isNotNull);
    await tester.sendEventToBinding(p.up());
    await tester.pump();
    expect(s.transform, isNotNull); // still running; release was ignored
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(s.transform, isNull);
  });

  testWidgets('viewport: press-release during transform does not pick', (tester) async {
    final s = await pumpApp(tester);
    final vp = find.byType(EditorViewport);
    final center = tester.getCenter(vp);
    final p = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(p.hover(center));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(s.transform, isNotNull);
    final before = Set.of(s.selectedObjects);
    await tester.sendEventToBinding(p.down(center, buttons: kPrimaryButton));
    await tester.sendEventToBinding(p.up());
    await tester.pump();
    // session got confirmed by the down, selection untouched
    expect(s.transform, isNull);
    expect(s.selectedObjects, before);
  });

  testWidgets('viewport: alt+A deselects, ctrl+S triggers save', (tester) async {
    final s = await pumpApp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(s.selectedObjects, isEmpty);
    // ctrl+S opens the save dialog through the onSave hook
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(find.text('Save Scene'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    // reselect for alt+A on empty
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
  });

  testWidgets('viewport: E extrudes in edit mode', (tester) async {
    final s = await pumpApp(tester);
    s.enterEditMode();
    s.setSelMode(SelMode.face);
    s.selFaces = {1};
    await tester.pumpWidget(ToasterApp(state: s));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(s.transform, isNotNull);
    s.cancelTransform();
  });

  testWidgets('viewport: pinch zoom on touch', (tester) async {
    final s = await pumpApp(tester);
    final vp = find.byType(EditorViewport);
    final center = tester.getCenter(vp);
    final dBefore = s.camera.distance;
    final p1 = TestPointer(1, PointerDeviceKind.touch);
    final p2 = TestPointer(2, PointerDeviceKind.touch);
    await tester.sendEventToBinding(p1.down(center - const Offset(40, 0)));
    await tester.sendEventToBinding(p2.down(center + const Offset(40, 0)));
    await tester.sendEventToBinding(p1.move(center - const Offset(80, 0)));
    await tester.sendEventToBinding(p2.move(center + const Offset(80, 0)));
    await tester.sendEventToBinding(p1.up());
    await tester.sendEventToBinding(p2.up());
    await tester.pump();
    expect(s.camera.distance, isNot(dBefore));
  });

  testWidgets('dialogs: save to file and clipboard', (tester) async {
    final s = await pumpApp(tester);
    final dir = Directory.systemTemp.createTempSync('toaster_dlg');
    await openMenu(tester, 'File');
    await tapMenuItem(tester, 'Save...');
    expect(find.text('Save Scene'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '${dir.path}/out.toast');
    await tester.tap(find.byType(FilledButton));
    await settle(tester);
    expect(File('${dir.path}/out.toast').existsSync(), isTrue);
    expect(s.filePath, contains('out.toast'));
    // clipboard path via direct call
    unawaited(showSaveDialog(tester.element(find.byType(EditorViewport))));
    await settle(tester);
    await tester.tap(find.text('Copy JSON'));
    await settle(tester);
    expect(_clipData, contains('"objects"'));
    dir.deleteSync(recursive: true);
  });

  testWidgets('dialogs: open from pasted JSON and file', (tester) async {
    final s = await pumpApp(tester);
    final saved = s.saveSceneText();
    s.newScene();
    unawaited(showOpenDialog(tester.element(find.byType(EditorViewport))));
    await settle(tester);
    expect(find.text('Open Scene'), findsOneWidget);
    // paste into the JSON field (second text field)
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).last, saved);
    await tester.tap(find.byType(FilledButton));
    await settle(tester);
    expect(s.scene.objects.length, 1);
    // file path load
    final dir = Directory.systemTemp.createTempSync('toaster_dlg2');
    File('${dir.path}/s.toast').writeAsStringSync(saved);
    unawaited(showOpenDialog(tester.element(find.byType(EditorViewport))));
    await settle(tester);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first, '${dir.path}/s.toast');
    await tester.tap(find.text('Load from file'));
    await settle(tester);
    expect(s.scene.objects.length, 1);
    // bad path shows error; cancel closes
    unawaited(showOpenDialog(tester.element(find.byType(EditorViewport))));
    await settle(tester);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first, '/no/such/file.toast');
    await tester.tap(find.text('Load from file'));
    await settle(tester);
    expect(find.textContaining('Could not read'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    dir.deleteSync(recursive: true);
  });

  testWidgets('dialogs: export and import obj', (tester) async {
    final s = await pumpApp(tester);
    final dir = Directory.systemTemp.createTempSync('toaster_dlg3');
    unawaited(showExportObjDialog(tester.element(find.byType(EditorViewport))));
    await settle(tester);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '${dir.path}/out.obj');
    await tester.tap(find.byType(FilledButton));
    await settle(tester);
    expect(File('${dir.path}/out.obj').readAsStringSync(), contains('o Cube'));
    // clipboard export
    unawaited(showExportObjDialog(tester.element(find.byType(EditorViewport))));
    await settle(tester);
    await tester.tap(find.text('Copy'));
    await settle(tester);
    // import pasted obj
    unawaited(showImportObjDialog(tester.element(find.byType(EditorViewport))));
    await settle(tester);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).last, 'v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n');
    await tester.tap(find.byType(FilledButton));
    await settle(tester);
    expect(s.scene.objects.any((o) => o.name == 'Imported'), isTrue);
    // import via file
    unawaited(showImportObjDialog(tester.element(find.byType(EditorViewport))));
    await settle(tester);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first, '${dir.path}/out.obj');
    await tester.tap(find.text('Load from file'));
    await settle(tester);
    expect(s.scene.objects.where((o) => o.name == 'Imported').length, 2);
    // bad path error + cancel
    unawaited(showImportObjDialog(tester.element(find.byType(EditorViewport))));
    await settle(tester);
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first, '/nope/x.obj');
    await tester.tap(find.text('Load from file'));
    await settle(tester);
    expect(find.textContaining('Could not read'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    dir.deleteSync(recursive: true);
  });

  testWidgets('golden: edit mode', (tester) async {
    final s = await pumpApp(tester);
    s.enterEditMode();
    s.setSelMode(SelMode.vertex);
    s.selVerts = {0, 4};
    await tester.pumpWidget(ToasterApp(state: s));
    await tester.pump();
    await expectLater(find.byType(ToasterApp), matchesGoldenFile('goldens/app_edit.png'));
  });

  testWidgets('golden: compact', (tester) async {
    await pumpApp(tester, size: const Size(420, 800));
    await expectLater(find.byType(ToasterApp), matchesGoldenFile('goldens/app_compact.png'));
  });

  testWidgets('golden: transform session', (tester) async {
    final s = await pumpApp(tester);
    s.setTool(Tool.move);
    s.beginTransform(TransformKind.grab, const Offset(400, 300), viewportHeight: 600);
    s.updateTransform(const Offset(460, 280));
    await tester.pumpWidget(ToasterApp(state: s));
    await tester.pump();
    await expectLater(find.byType(ToasterApp), matchesGoldenFile('goldens/app_transform.png'));
    s.cancelTransform();
  });

  testWidgets('dialogs: no-filesystem fallbacks', (tester) async {
    final s = await pumpApp(tester);
    fileStoreSupported = false;
    addTearDown(() => fileStoreSupported = true);
    // save dialog shows copy-only hint
    unawaited(showSaveDialog(tester.element(find.byType(EditorViewport))));
    await settle(tester);
    expect(find.textContaining('Filesystem not available'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    // open dialog shows paste-only layout
    unawaited(showOpenDialog(tester.element(find.byType(EditorViewport))));
    await settle(tester);
    expect(find.text('Paste scene JSON'), findsOneWidget);
    // invalid JSON -> open failed hint
    await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).last,
        'not json at all');
    await tester.tap(find.byType(FilledButton));
    await settle(tester);
    expect(s.statusHint, contains('Open failed'));
    // export dialog shows copy-only hint
    unawaited(showExportObjDialog(tester.element(find.byType(EditorViewport))));
    await settle(tester);
    expect(find.text('Copy the OBJ text to your clipboard.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
  });

  testWidgets('dialogs: save to unwritable path fails with hint', (tester) async {
    final s = await pumpApp(tester);
    unawaited(showSaveDialog(tester.element(find.byType(EditorViewport))));
    await settle(tester);
    await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
        '/proc/0/definitely-not-writable.toast');
    await tester.tap(find.byType(FilledButton));
    await settle(tester);
    expect(s.statusHint, contains('Save failed'));
  });
}
