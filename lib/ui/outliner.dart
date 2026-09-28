import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/scene.dart';
import 'theme.dart';

/// Scene object list, Blender-outliner style.
class OutlinerPanel extends StatelessWidget {
  const OutlinerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(title: 'Outliner', trailing: Text(
          '${app.scene.objects.length} objects',
          style: T.hint,
        )),
        Expanded(
          child: app.scene.objects.isEmpty
              ? Center(child: Text('Empty scene\nAdd → Cube', textAlign: TextAlign.center, style: T.hint))
              : ListView.builder(
                  itemCount: app.scene.objects.length,
                  itemBuilder: (context, i) {
                    final o = app.scene.objects[i];
                    final sel = app.selectedObjects.contains(i);
                    final active = app.activeObject == i || app.editTarget == i;
                    return InkWell(
                      onTap: () => app.selectObject(i, additive: false),
                      onLongPress: () => app.selectObject(i, additive: true),
                      child: Container(
                        height: 26,
                        color: active
                            ? T.accentSoft
                            : sel
                                ? T.accentSoft.withValues(alpha: 0.45)
                                : Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Icon(
                              _iconFor(o),
                              size: 13,
                              color: sel ? T.selection : T.textDim,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                o.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: o.visible ? T.text : T.textDim,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            InkWell(
                              onTap: () => app.setObjectVisible(i, !o.visible),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  o.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  size: 13,
                                  color: T.textDim,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  IconData _iconFor(SceneObject o) {
    if (o.mesh.faces.isEmpty) return Icons.linear_scale;
    final n = o.name.toLowerCase();
    if (n.contains('sphere')) return Icons.circle_outlined;
    if (n.contains('plane') || n.contains('grid')) return Icons.grid_on;
    if (n.contains('cylinder') || n.contains('cone')) return Icons.invert_colors;
    if (n.contains('torus')) return Icons.donut_large;
    if (n.contains('monkey')) return Icons.face;
    return Icons.inventory_2_outlined;
  }

}

/// Shared section header used by the side panels.
class PanelHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const PanelHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) => Container(
        height: 28,
        color: T.panelAlt,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: T.text)),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
      );
}
