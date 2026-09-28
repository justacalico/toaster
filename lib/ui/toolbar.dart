import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'theme.dart';

/// Left-side tool rail (wide) or bottom row (compact).
class ToolRail extends StatelessWidget {
  final bool compact;

  const ToolRail({super.key, this.compact = false});

  static const _tools = [
    (Tool.select, Icons.near_me_outlined, 'Select'),
    (Tool.move, Icons.open_with, 'Move (G)'),
    (Tool.rotate, Icons.rotate_90_degrees_ccw, 'Rotate (R)'),
    (Tool.scale, Icons.zoom_out_map, 'Scale (S)'),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final children = <Widget>[
      for (final (t, icon, label) in _tools)
        _ToolButton(
          icon: icon,
          label: label,
          active: app.tool == t,
          onTap: () => app.setTool(t),
        ),
      if (app.mode == EditorMode.edit) ...[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          child: Divider(height: 1),
        ),
        _ToolButton(
          icon: Icons.unarchive_outlined,
          label: 'Extrude (E)',
          active: false,
          onTap: app.extrude,
        ),
        _ToolButton(
          icon: Icons.crop_square,
          label: 'Inset (I)',
          active: false,
          onTap: () => app.inset(0.25),
        ),
        _ToolButton(
          icon: Icons.grid_4x4,
          label: 'Subdivide',
          active: false,
          onTap: app.subdivideSelected,
        ),
        _ToolButton(
          icon: Icons.change_history,
          label: 'Fill (F)',
          active: false,
          onTap: app.fillFaces,
        ),
      ],
    ];

    if (compact) {
      return SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          children: children
              .map((w) => w is Divider ? const VerticalDivider(width: 16) : w)
              .toList(),
        ),
      );
    }
    return Container(
      width: 52,
      color: T.panel,
      child: ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: children),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      preferBelow: false,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: active ? T.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: active ? Border.all(color: T.accent) : null,
          ),
          child: Icon(icon, size: 20, color: active ? Colors.white : T.textDim),
        ),
      ),
    );
  }
}
