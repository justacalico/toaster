import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'dialogs.dart';
import 'menus.dart';
import 'outliner.dart';
import 'panels.dart';
import 'status_bar.dart';
import 'theme.dart';
import 'toolbar.dart';
import 'viewport.dart';

/// Adaptive root scaffold. Compact (<840px): full-bleed viewport with a
/// bottom tool row and a sheet for panels. Wide: classic Blender layout —
/// header, left tools, center viewport, right outliner+properties.
class RootShell extends StatelessWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 840;
        return Scaffold(
          backgroundColor: T.bg,
          body: SafeArea(
            child: compact ? const _CompactLayout() : const _WideLayout(),
          ),
        );
      },
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppMenuBar(),
        const Divider(height: 1),
        Expanded(
          child: Row(
            children: [
              const ToolRail(),
              const VerticalDivider(width: 1),
              const Expanded(child: _ViewportRegion()),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 280,
                child: Column(
                  children: [
                    const Expanded(flex: 4, child: OutlinerPanel()),
                    const Divider(height: 1),
                    const Expanded(flex: 6, child: PropertiesPanel()),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        const StatusBar(),
      ],
    );
  }
}

class _ViewportRegion extends StatelessWidget {
  const _ViewportRegion();

  @override
  Widget build(BuildContext context) => EditorViewport(onSave: () => showSaveDialog(context));
}

class _CompactLayout extends StatelessWidget {
  const _CompactLayout();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppMenuBar(compact: true),
        const Divider(height: 1),
        const Expanded(child: _ViewportRegion()),
        const Divider(height: 1),
        SizedBox(
          height: 46,
          child: Row(
            children: [
              const Expanded(child: ToolRail(compact: true)),
              IconButton(
                icon: const Icon(Icons.layers_outlined, size: 18),
                tooltip: 'Panels',
                onPressed: () => _showPanels(context),
              ),
            ],
          ),
        ),
        const StatusBar(),
      ],
    );
  }

  void _showPanels(BuildContext context) {
    final app = context.read<AppState>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: T.panel,
      isScrollControlled: true,
      builder: (context) => ChangeNotifierProvider.value(
        value: app,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: const Column(
            children: [
              Expanded(flex: 4, child: OutlinerPanel()),
              Divider(height: 1),
              Expanded(flex: 6, child: PropertiesPanel()),
            ],
          ),
        ),
      ),
    );
  }
}
