import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:toaster/core/file_store.dart';
import 'package:toaster/core/primitives.dart';
import 'package:toaster/core/scene.dart';
import 'package:toaster/core/serializer.dart';
import 'package:toaster/core/undo.dart';
import 'package:toaster/core/vec3.dart';
import 'package:toaster/core/modifiers.dart';

void main() {
  group('serializer', () {
    test('scene JSON roundtrip', () {
      final scene = Scene(objects: [
        SceneObject(
          name: 'Cube',
          mesh: Primitives.cube(),
          location: const Vec3(1, 2, 3),
          rotation: const Vec3(0.1, 0.2, 0.3),
          scale: const Vec3(2, 1, 1),
          visible: true,
          smoothShading: true,
          modifiers: [MirrorModifier(), ArrayModifier(count: 3)],
        )..mesh.edges.add((0, 3)),
      ]);
      final text = Serializer.encode(scene);
      final back = Serializer.decode(text);
      expect(back.objects.length, 1);
      final o = back.objects[0];
      expect(o.name, 'Cube');
      expect(o.location, const Vec3(1, 2, 3));
      expect(o.scale, const Vec3(2, 1, 1));
      expect(o.smoothShading, isTrue);
      expect(o.mesh.vertices.length, 8);
      expect(o.mesh.edges.length, 1);
      expect(o.modifiers.length, 2);
      expect(back.showGrid, isTrue);
    });

    test('decode rejects non-scene data', () {
      expect(() => Serializer.decode('[1,2,3]'), throwsFormatException);
      expect(Serializer.decode('{"objects":[]}').objects, isEmpty);
    });

    test('obj export writes world-space verts and faces', () {
      final scene = Scene(objects: [
        SceneObject(name: 'Box', mesh: Primitives.cube(), location: const Vec3(10, 0, 0)),
        SceneObject(name: 'Hidden', mesh: Primitives.cube(), visible: false),
      ]);
      final obj = Serializer.toObj(scene);
      expect(obj, contains('o Box'));
      expect(obj, isNot(contains('o Hidden')));
      expect(obj, contains('v 11.0 -1.0 -1.0'));
      expect(obj, contains('f 1 4 3 2'));
    });

    test('obj import parses v/f with slashes and negative indices', () {
      final mesh = Serializer.fromObj('''
# comment
v 0 0 0
v 1 0 0
v 1 1 0
v 0 1 0
vn 0 0 1
f 1/1/1 2/2/1 3/3/1
f -4 -2 -1
o thing
f 1 2 3 4
''');
      expect(mesh.vertices.length, 4);
      expect(mesh.faces.length, 3);
      expect(mesh.faces[1], [0, 2, 3]);
    });
  });

  group('file store (io)', () {
    test('save and read roundtrip', () async {
      final dir = await Directory.systemTemp.createTemp('toaster_test');
      final path = '${dir.path}/scene.toast';
      expect(fileStoreSupported, isTrue);
      expect(await saveTextFile(path, 'hello'), path);
      expect(await readTextFile(path), 'hello');
      expect(await readTextFile('${dir.path}/nope.toast'), isNull);
      await dir.delete(recursive: true);
    });

    test('save to invalid path returns null', () async {
      expect(await saveTextFile('/nonexistent-dir-xyz/../\x00bad', 'x'), isNull);
    });
  });

  group('undo stack', () {
    test('push/pop/redo', () {
      final u = UndoStack<int>(maxDepth: 3);
      expect(u.canUndo, isFalse);
      u.push(1);
      u.push(2);
      expect(u.undoCount, 2);
      expect(u.undo(3), 2); // restores state 2, redo holds 3
      expect(u.canRedo, isTrue);
      expect(u.redo(2), 3); // restores 3, undo holds 2 again
      expect(u.undoCount, 2);
    });

    test('push clears redo and caps depth', () {
      final u = UndoStack<int>(maxDepth: 2);
      u.push(1);
      u.undo(0);
      u.push(5);
      expect(u.canRedo, isFalse);
      u.push(6);
      u.push(7);
      expect(u.undoCount, 2); // capped
      expect(u.pop(), 7);
      expect(u.pop(), 6);
      expect(u.pop(), isNull);
    });

    test('pop returns null when empty; clear wipes both', () {
      final u = UndoStack<int>();
      expect(u.pop(), isNull);
      expect(u.popRedo(), isNull);
      u.push(1);
      u.pushRedo(2);
      u.clear();
      expect(u.canUndo, isFalse);
      expect(u.canRedo, isFalse);
    });
  });
}
