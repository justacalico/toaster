import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/picking.dart';
import 'viewport_painter.dart';

/// The interactive 3D viewport: orbit/pan/zoom, click select, gizmo drags,
/// and the full Blender-style hotkey layer.
class EditorViewport extends StatefulWidget {
  final VoidCallback? onSave;

  const EditorViewport({super.key, this.onSave});

  @override
  State<EditorViewport> createState() => ViewportState();
}

class ViewportState extends State<EditorViewport> {
  final _focus = FocusNode();
  Offset _lastPointer = Offset.zero;
  Size _size = Size.zero;
  Offset? _downPos;
  int? _dragAxis;
  int? _hoverAxis;
  double _lastScale = 1;

  AppState get app => context.read<AppState>();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  int? _gizmoHit(Offset pos) {
    for (final (axis, a, b) in gizmoSegments(app, _size)) {
      if (pointSegmentDist(pos.dx, pos.dy, a.dx, a.dy, b.dx, b.dy) < 81) {
        return axis;
      }
      // tip handle hit area
      if ((b - pos).distanceSquared < 121) return axis;
    }
    return null;
  }

  void _onPointerDown(PointerDownEvent e) {
    _lastPointer = e.localPosition;
    _focus.requestFocus();
    if (e.buttons & kMiddleMouseButton != 0 ||
        (e.buttons & kPrimaryButton != 0 && HardwareKeyboard.instance.isAltPressed)) {
      return; // handled in move
    }
    if (e.buttons & kSecondaryMouseButton != 0) {
      if (app.transform != null) app.cancelTransform();
      return;
    }
    if (e.buttons & kPrimaryButton != 0) {
      if (app.transform != null) {
        app.confirmTransform();
        return;
      }
      if (app.tool != Tool.select) {
        final axis = _gizmoHit(e.localPosition);
        if (axis != null) {
          final kind = switch (app.tool) {
            Tool.move => TransformKind.grab,
            Tool.rotate => TransformKind.rotate,
            Tool.scale => TransformKind.scale,
            Tool.select => TransformKind.grab, // coverage:ignore-line
          };
          app.beginTransform(kind, e.localPosition, viewportHeight: _size.height, axis: axis);
          _dragAxis = axis;
          return;
        }
      }
      _downPos = e.localPosition;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    final delta = e.localPosition - _lastPointer;
    _lastPointer = e.localPosition;
    if (app.transform != null) {
      if (_dragAxis != null || e.buttons == 0 || e.buttons & kPrimaryButton != 0) {
        app.updateTransform(e.localPosition);
      }
      return;
    }
    if (e.buttons & kMiddleMouseButton != 0) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        app.camera.pan(delta.dx, delta.dy, _size.height);
      } else {
        app.camera.orbit(delta.dx * 0.008, delta.dy * 0.008);
      }
      setState(() {});
      return;
    }
    if (e.buttons & kPrimaryButton != 0 && HardwareKeyboard.instance.isAltPressed) {
      app.camera.orbit(delta.dx * 0.008, delta.dy * 0.008);
      setState(() {});
      return;
    }
  }

  void _onPointerHover(PointerHoverEvent e) {
    _lastPointer = e.localPosition;
    if (app.transform != null && _dragAxis == null) {
      app.updateTransform(e.localPosition);
      return;
    }
    if (app.transform == null && app.tool != Tool.select) {
      final hit = _gizmoHit(e.localPosition);
      if (hit != _hoverAxis) setState(() => _hoverAxis = hit);
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_dragAxis != null) {
      app.confirmTransform();
      _dragAxis = null;
      return;
    }
    if (app.transform != null) {
      // a press-release during a hotkeyed transform is a confirm/cancel
      // gesture, never a selection click
      _downPos = null;
      return;
    }
    if (_downPos != null &&
        (e.localPosition - _downPos!).distance < 5 &&
        e.buttons & kPrimaryButton == 0) {
      app.pickAt(e.localPosition, _size.width, _size.height,
          additive: HardwareKeyboard.instance.isShiftPressed);
    }
    _downPos = null;
  }

  void _onScroll(PointerScrollEvent e) {
    app.camera.zoom(e.scrollDelta.dy > 0 ? 1.1 : 1 / 1.1);
    setState(() {});
  }

  void _onScaleStart(ScaleStartDetails d) {
    _lastScale = 1;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (app.transform != null) return;
    if (d.scale != 1 && (d.scale - _lastScale).abs() > 0.001) {
      app.camera.zoom(_lastScale / d.scale);
      _lastScale = d.scale;
    } else if (d.pointerCount == 1 || d.focalPointDelta.distance > 0) {
      app.camera.orbit(d.focalPointDelta.dx * 0.008, d.focalPointDelta.dy * 0.008);
    }
    setState(() {});
  }

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;

    // transform session keys
    if (app.transform != null) {
      if (k == LogicalKeyboardKey.escape) {
        app.cancelTransform();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
        app.confirmTransform();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyX) {
        app.constrainAxis(0);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyY) {
        app.constrainAxis(1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyZ) {
        app.constrainAxis(2);
        return KeyEventResult.handled;
      }
      // every other key is dead while a transform session is running
      return KeyEventResult.handled;
    }

    // global
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      if (shift) {
        app.redo();
      } else {
        app.undo();
      }
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyY) {
      app.redo();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyS) {
      widget.onSave?.call();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyJ) {
      app.joinSelected();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyN) {
      app.newScene();
      return KeyEventResult.handled;
    }

    if (k == LogicalKeyboardKey.tab) {
      app.toggleEditMode();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      app.deselectAll();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyA) {
      if (alt) {
        app.deselectAll();
      } else {
        app.selectAll();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyG) {
      app.beginTransform(TransformKind.grab, _lastPointer, viewportHeight: _size.height);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyR) {
      app.beginTransform(TransformKind.rotate, _lastPointer, viewportHeight: _size.height);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyS) {
      app.beginTransform(TransformKind.scale, _lastPointer, viewportHeight: _size.height);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyD && shift) {
      app.duplicateSelected();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.keyX && !ctrl) {
      app.deleteSelected();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyZ) {
      app.cycleShading();
      return KeyEventResult.handled;
    }

    if (app.mode == EditorMode.edit) {
      if (k == LogicalKeyboardKey.digit1) {
        app.setSelMode(SelMode.vertex);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.digit2) {
        app.setSelMode(SelMode.edge);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.digit3) {
        app.setSelMode(SelMode.face);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyE) {
        app.extrude();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyI) {
        app.inset(0.25);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyF) {
        app.fillFaces();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyM) {
        app.mergeByDistance();
        return KeyEventResult.handled;
      }
    }

    // views: numpad always, top-row digits in object mode
    final viewKeys = {
      LogicalKeyboardKey.numpad1: 'front',
      LogicalKeyboardKey.numpad3: 'right',
      LogicalKeyboardKey.numpad7: 'top',
      LogicalKeyboardKey.numpad9: 'bottom',
    };
    if (app.mode == EditorMode.object) {
      viewKeys[LogicalKeyboardKey.digit1] = 'front';
      viewKeys[LogicalKeyboardKey.digit3] = 'right';
      viewKeys[LogicalKeyboardKey.digit7] = 'top';
      viewKeys[LogicalKeyboardKey.digit9] = 'bottom';
    }
    if (viewKeys.containsKey(k)) {
      app.setViewPreset(viewKeys[k]!);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.numpad5 || (app.mode == EditorMode.object && k == LogicalKeyboardKey.digit5)) {
      app.togglePerspective();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.numpadDecimal || k == LogicalKeyboardKey.period) {
      app.frameSelected(_size.aspectRatio);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.home) {
      app.deselectAll();
      app.frameSelected(_size.aspectRatio);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = Size(constraints.maxWidth, constraints.maxHeight);
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerHover: _onPointerHover,
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) _onScroll(e);
            },
            child: GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              behavior: HitTestBehavior.opaque,
              child: CustomPaint(
                size: Size.infinite,
                painter: ViewportPainter(app, gizmoHoverAxis: _hoverAxis),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}
