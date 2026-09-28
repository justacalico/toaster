import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/primitives.dart';
import '../core/renderer.dart';
import 'dialogs.dart';
import 'theme.dart';

/// Top menu bar + mode/shading controls, Blender-header style.
class AppMenuBar extends StatelessWidget {
  final bool compact;

  const AppMenuBar({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Container(
      height: 34,
      color: T.panel,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          // logo mark
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.breakfast_dining, size: 16, color: T.selection),
          ),
          Flexible(
            child: MenuBar(
              style: const MenuStyle(
                backgroundColor: WidgetStatePropertyAll(Colors.transparent),
                elevation: WidgetStatePropertyAll(0),
                padding: WidgetStatePropertyAll(EdgeInsets.zero),
              ),
              children: [
                _sub('File', [
                  _mi('New', app.newScene, shortcut: 'Ctrl+N'),
                  _mi('Open...', () => showOpenDialog(context), shortcut: ''),
                  _mi('Save...', () => showSaveDialog(context), shortcut: 'Ctrl+S'),
                  const _Sep(),
                  _mi('Import OBJ...', () => showImportObjDialog(context)),
                  _mi('Export OBJ...', () => showExportObjDialog(context)),
                ]),
                _sub('Edit', [
                  _mi('Undo', app.undo, shortcut: 'Ctrl+Z'),
                  _mi('Redo', app.redo, shortcut: 'Ctrl+Y'),
                  const _Sep(),
                  _mi('Duplicate', app.duplicateSelected, shortcut: 'Shift+D'),
                  _mi('Join', app.joinSelected, shortcut: 'Ctrl+J'),
                  _mi('Delete', app.deleteSelected, shortcut: 'Del'),
                ]),
                _sub('Add', [
                  for (final p in Primitives.names) _mi(p, () => app.addPrimitive(p)),
                ]),
                _sub('Mesh', [
                  _mi('Extrude', app.extrude, shortcut: 'E'),
                  _mi('Inset', () => app.inset(0.25), shortcut: 'I'),
                  _mi('Subdivide', app.subdivideSelected),
                  _mi('Fill', app.fillFaces, shortcut: 'F'),
                  _mi('Merge by Distance', app.mergeByDistance, shortcut: 'M'),
                  _mi('Flip Normals', app.flipNormals),
                  _mi('Shade Smooth / Flat', app.toggleSmoothShading),
                ]),
                _sub('View', [
                  _mi('Front', () => app.setViewPreset('front'), shortcut: '1'),
                  _mi('Right', () => app.setViewPreset('right'), shortcut: '3'),
                  _mi('Top', () => app.setViewPreset('top'), shortcut: '7'),
                  _mi('Bottom', () => app.setViewPreset('bottom'), shortcut: '9'),
                  const _Sep(),
                  _mi('Toggle Perspective/Ortho', app.togglePerspective, shortcut: '5'),
                  _mi('Frame Selected', () => app.frameSelected(16 / 9), shortcut: '.'),
                  const _Sep(),
                  _mi('Grid', () {
                    app.scene.showGrid = !app.scene.showGrid;
                    app.refresh();
                  }),
                  _mi('Overlays', app.toggleOverlays),
                ]),
                _sub('Help', [
                  _mi('About toaster', () => showToasterAboutDialog(context)),
                ]),
              ],
            ),
          ),
          // mode + shading controls
          _ModeSwitcher(app: app),
          const SizedBox(width: 6),
          _ShadingSwitcher(app: app),
          if (!compact) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: app.toggleSnap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: app.snapEnabled ? T.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: app.snapEnabled ? T.accent : T.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.grid_goldenratio, size: 12, color: app.snapEnabled ? T.text : T.textDim),
                    const SizedBox(width: 4),
                    Text('Snap', style: TextStyle(fontSize: 11, color: app.snapEnabled ? T.text : T.textDim)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sub(String label, List<Widget> items) => SubmenuButton(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
        ),
        menuChildren: items,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      );

  Widget _mi(String label, VoidCallback onTap, {String shortcut = ''}) => MenuItemButton(
        onPressed: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            if (shortcut.isNotEmpty) ...[
              const SizedBox(width: 24),
              Text(shortcut, style: T.hint.copyWith(fontSize: 10)),
            ],
          ],
        ),
      );
}

class _Sep extends StatelessWidget {
  const _Sep();

  @override
  Widget build(BuildContext context) => const Divider(height: 6);
}

class _ModeSwitcher extends StatelessWidget {
  final AppState app;

  const _ModeSwitcher({required this.app});

  @override
  Widget build(BuildContext context) {
    final edit = app.mode == EditorMode.edit;
    return Row(
      children: [
        _chip('Object', !edit, () {
          if (edit) app.exitEditMode();
        }),
        const SizedBox(width: 2),
        _chip('Edit', edit, () {
          if (!edit) app.enterEditMode();
        }),
        if (edit) ...[
          const SizedBox(width: 6),
          for (final (m, l) in [
            (SelMode.vertex, 'V'),
            (SelMode.edge, 'E'),
            (SelMode.face, 'F')
          ])
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: _chip(l, app.selMode == m, () => app.setSelMode(m)),
            ),
        ],
      ],
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: active ? T.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: active ? T.accent : T.border),
          ),
          child: Text(label, style: TextStyle(fontSize: 11, color: active ? T.text : T.textDim)),
        ),
      );
}

class _ShadingSwitcher extends StatelessWidget {
  final AppState app;

  const _ShadingSwitcher({required this.app});

  @override
  Widget build(BuildContext context) {
    const icons = {
      ShadingMode.wireframe: Icons.grid_3x3,
      ShadingMode.solid: Icons.circle,
      ShadingMode.materialPreview: Icons.circle_outlined,
    };
    return Row(
      children: [
        for (final s in ShadingMode.values)
          InkWell(
            onTap: () => app.setShading(s),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: app.shading == s ? T.accentSoft : Colors.transparent,
                border: Border.all(color: app.shading == s ? T.accent : T.border),
                borderRadius: s == ShadingMode.wireframe
                    ? const BorderRadius.horizontal(left: Radius.circular(4))
                    : s == ShadingMode.materialPreview
                        ? const BorderRadius.horizontal(right: Radius.circular(4))
                        : BorderRadius.zero,
              ),
              child: Icon(icons[s], size: 13, color: app.shading == s ? T.text : T.textDim),
            ),
          ),
      ],
    );
  }
}
