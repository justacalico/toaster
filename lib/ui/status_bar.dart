import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'theme.dart';

/// Bottom status strip: mode, selection, hints, undo depth.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.transform;
    return Container(
      height: 24,
      color: T.panel,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(
            app.mode == EditorMode.object ? 'Object Mode' : 'Edit Mode · ${app.selMode.name}',
            style: const TextStyle(fontSize: 11, color: T.text),
          ),
          _sep(),
          Text(
            app.mode == EditorMode.object
                ? '${app.selectedObjects.length} selected'
                : '${app.selectionCount} selected',
            style: T.hint,
          ),
          _sep(),
          Text('Tool: ${app.tool.name}', style: T.hint),
          if (app.dirty) ...[
            _sep(),
            Text('● unsaved', style: T.hint.copyWith(color: T.selection)),
          ],
          const Spacer(),
          if (t != null)
            Text(t.label, style: T.mono.copyWith(color: T.selection))
          else if (app.statusHint.isNotEmpty)
            Text(app.statusHint, style: T.hint)
          else
            Text(
              app.mode == EditorMode.object
                  ? 'G/R/S transform · Tab edit · MMB orbit'
                  : 'E extrude · I inset · F fill · 1/2/3 select mode',
              style: T.hint,
            ),
        ],
      ),
    );
  }

  Widget _sep() => Container(
        width: 1,
        height: 12,
        color: T.border,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );
}
