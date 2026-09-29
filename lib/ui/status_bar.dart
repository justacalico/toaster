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
          Flexible(
            child: Text(
              app.mode == EditorMode.object ? 'Object Mode' : 'Edit · ${app.selMode.name}',
              style: const TextStyle(fontSize: 11, color: T.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _sep(),
          Flexible(
            child: Text(
              app.mode == EditorMode.object
                  ? '${app.selectedObjects.length} selected'
                  : '${app.selectionCount} selected',
              style: T.hint,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _sep(),
          Flexible(
            child: Text('Tool: ${app.tool.name}', style: T.hint, overflow: TextOverflow.ellipsis),
          ),
          if (app.dirty) ...[
            _sep(),
            Text('● unsaved', style: T.hint.copyWith(color: T.selection)),
          ],
          const Spacer(),
          if (t != null)
            Flexible(
              child: Text(t.label,
                  style: T.mono.copyWith(color: T.selection), overflow: TextOverflow.ellipsis),
            )
          else if (app.statusHint.isNotEmpty)
            Flexible(
              child: Text(app.statusHint, style: T.hint, overflow: TextOverflow.ellipsis),
            )
          else
            Flexible(
              child: Text(
                app.mode == EditorMode.object
                    ? 'G/R/S transform · Tab edit · MMB orbit'
                    : 'E extrude · I inset · F fill · 1/2/3 select mode',
                style: T.hint,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
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
