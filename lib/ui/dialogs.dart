import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/file_store.dart';
import 'theme.dart';

/// Save: writes .toast JSON to a path (desktop) and/or the clipboard.
Future<void> showSaveDialog(BuildContext context) async {
  final app = context.read<AppState>();
  final nameC = TextEditingController(text: app.filePath ?? 'untitled.toast');
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: T.panelAlt,
      title: const Text('Save Scene', style: TextStyle(fontSize: 15)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Scene data (.toast JSON)', style: T.hint),
          const SizedBox(height: 8),
          if (fileStoreSupported)
            TextField(
              controller: nameC,
              style: T.mono,
              decoration: const InputDecoration(labelText: 'File path'),
            )
          else
            Text('Filesystem not available on this platform. Copy to clipboard instead.',
                style: T.hint),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, 'clipboard'),
          child: const Text('Copy JSON'),
        ),
        if (fileStoreSupported)
          FilledButton(
            onPressed: () => Navigator.pop(context, nameC.text),
            child: const Text('Save'),
          ),
      ],
    ),
  );
  if (result == null) return;
  if (result == 'clipboard') {
    await Clipboard.setData(ClipboardData(text: app.saveSceneText()));
    app.setHint('Scene JSON copied to clipboard');
    return;
  }
  final path = await saveTextFile(result, app.saveSceneText());
  if (path != null) {
    app.filePath = path;
    app.dirty = false;
    app.setHint('Saved to $path');
  } else {
    app.setHint('Save failed: cannot write $result');
  }
}

/// Open: reads a .toast file by path, or accepts pasted JSON.
Future<void> showOpenDialog(BuildContext context) async {
  final app = context.read<AppState>();
  final pathC = TextEditingController(text: app.filePath ?? 'scene.toast');
  final textC = TextEditingController();
  String? loadError;
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: T.panelAlt,
        title: const Text('Open Scene', style: TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (fileStoreSupported) ...[
                TextField(
                  controller: pathC,
                  style: T.mono,
                  decoration: const InputDecoration(labelText: 'File path'),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () async {
                      final text = await readTextFile(pathC.text);
                      if (text == null) {
                        setState(() => loadError = 'Could not read ${pathC.text}');
                      } else {
                        if (!context.mounted) return;
                        Navigator.pop(context, 'file:$text');
                      }
                    },
                    child: const Text('Load from file'),
                  ),
                ),
                const Divider(),
                Text('or paste scene JSON', style: T.hint),
              ] else
                Text('Paste scene JSON', style: T.hint),
              const SizedBox(height: 6),
              TextField(
                controller: textC,
                maxLines: 5,
                style: T.mono.copyWith(fontSize: 10),
                decoration: const InputDecoration(hintText: '{ "version": 1, ... }'),
              ),
              if (loadError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(loadError!, style: const TextStyle(fontSize: 11, color: T.danger)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'text:${textC.text}'),
            child: const Text('Open'),
          ),
        ],
      ),
    ),
  );
  if (choice == null) return;
  // both 'file:' and 'text:' prefixes are 5 chars; payload follows
  final text = choice.substring(5);
  try {
    app.loadSceneText(text);
    if (choice.startsWith('file:')) app.filePath = pathC.text;
    app.setHint('Scene loaded');
  } catch (e) {
    app.setHint('Open failed: invalid scene file');
  }
}

/// Export OBJ: file on desktop, clipboard elsewhere.
Future<void> showExportObjDialog(BuildContext context) async {
  final app = context.read<AppState>();
  final nameC = TextEditingController(text: 'scene.obj');
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: T.panelAlt,
      title: const Text('Export OBJ', style: TextStyle(fontSize: 15)),
      content: fileStoreSupported
          ? TextField(
              controller: nameC,
              style: T.mono,
              decoration: const InputDecoration(labelText: 'File path'),
            )
          : Text('Copy the OBJ text to your clipboard.', style: T.hint),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, 'clipboard'),
          child: const Text('Copy'),
        ),
        if (fileStoreSupported)
          FilledButton(
            onPressed: () => Navigator.pop(context, nameC.text),
            child: const Text('Export'),
          ),
      ],
    ),
  );
  if (result == null) return;
  if (result == 'clipboard') {
    await Clipboard.setData(ClipboardData(text: app.exportObj()));
    app.setHint('OBJ copied to clipboard');
    return;
  }
  final path = await saveTextFile(result, app.exportObj());
  app.setHint(path != null ? 'Exported to $path' : 'Export failed: cannot write $result');
}

/// Import OBJ from a file path or pasted text.
Future<void> showImportObjDialog(BuildContext context) async {
  final app = context.read<AppState>();
  final pathC = TextEditingController(text: 'model.obj');
  final textC = TextEditingController();
  String? loadError;
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: T.panelAlt,
        title: const Text('Import OBJ', style: TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (fileStoreSupported) ...[
                TextField(
                  controller: pathC,
                  style: T.mono,
                  decoration: const InputDecoration(labelText: 'File path'),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () async {
                      final text = await readTextFile(pathC.text);
                      if (text == null) {
                        setState(() => loadError = 'Could not read ${pathC.text}');
                      } else {
                        if (!context.mounted) return;
                        Navigator.pop(context, text);
                      }
                    },
                    child: const Text('Load from file'),
                  ),
                ),
                const Divider(),
              ],
              TextField(
                controller: textC,
                maxLines: 5,
                style: T.mono.copyWith(fontSize: 10),
                decoration: const InputDecoration(hintText: 'v 0 0 0\nf 1 2 3 ...'),
              ),
              if (loadError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(loadError!, style: const TextStyle(fontSize: 11, color: T.danger)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, textC.text),
            child: const Text('Import'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || choice.isEmpty) return;
  app.importObj(choice);
}

Future<void> showToasterAboutDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const AlertDialog(
      backgroundColor: T.panelAlt,
      title: Text('toaster', style: TextStyle(fontSize: 16)),
      content: Text(
        'A pocket-sized Blender-style 3D modeler.\n\n'
        'MMB orbit • Shift+MMB pan • wheel zoom\n'
        'G/R/S transform • X/Y/Z axis lock\n'
        'Tab edit mode • E extrude • I inset\n'
        'A select all • Del delete • Ctrl+Z undo',
        style: TextStyle(fontSize: 12, height: 1.5),
      ),
    ),
  );
}
