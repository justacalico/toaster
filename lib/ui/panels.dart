import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/modifiers.dart';
import '../core/vec3.dart';
import 'outliner.dart';
import 'theme.dart';

/// Right-hand properties area: Item transform, Material, Modifiers.
class PropertiesPanel extends StatefulWidget {
  const PropertiesPanel({super.key});

  @override
  State<PropertiesPanel> createState() => _PropertiesPanelState();
}

class _PropertiesPanelState extends State<PropertiesPanel> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final obj = app.mode == EditorMode.edit ? app.editObj : app.activeObj;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: T.panelAlt,
          child: Row(
            children: [
              for (final (i, label) in ['Item', 'Material', 'Modifiers'].indexed)
                Expanded(
                  child: _TabChip(
                    label: label,
                    active: _tab == i,
                    onTap: () => setState(() => _tab = i),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: obj == null
              ? Center(child: Text('Nothing selected', style: T.hint))
              : switch (_tab) {
                  0 => _ItemTab(objName: obj.name),
                  1 => const _MaterialTab(),
                  _ => const _ModifiersTab(),
                },
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: active ? T.accent : Colors.transparent, width: 2)),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 11.5, color: active ? T.text : T.textDim),
              overflow: TextOverflow.ellipsis),
        ),
      );
}

// ---------- Item tab ----------

class _ItemTab extends StatelessWidget {
  final String objName;

  const _ItemTab({required this.objName});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final o = (app.mode == EditorMode.edit ? app.editObj : app.activeObj)!;
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _NameField(name: o.name),
        const SizedBox(height: 10),
        _Vec3Row(label: 'Location', value: o.location, onChanged: app.setActiveLocation),
        _Vec3Row(
          label: 'Rotation',
          value: Vec3(
            o.rotation.x * 180 / math.pi,
            o.rotation.y * 180 / math.pi,
            o.rotation.z * 180 / math.pi,
          ),
          onChanged: (v) => app.setActiveRotation(
              Vec3(v.x * math.pi / 180, v.y * math.pi / 180, v.z * math.pi / 180)),
          step: 5,
        ),
        _Vec3Row(label: 'Scale', value: o.scale, onChanged: app.setActiveScale, step: 0.1),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SmallButton(
                label: o.smoothShading ? 'Shade Flat' : 'Shade Smooth',
                onTap: app.toggleSmoothShading,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NameField extends StatefulWidget {
  final String name;

  const _NameField({required this.name});

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _c = TextEditingController(text: widget.name);

  @override
  void didUpdateWidget(_NameField old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name && _c.text != widget.name) _c.text = widget.name;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      style: const TextStyle(fontSize: 12),
      decoration: const InputDecoration(labelText: 'Name'),
      onSubmitted: (v) => context.read<AppState>().setActiveName(v),
    );
  }
}

class _Vec3Row extends StatelessWidget {
  final String label;
  final Vec3 value;
  final ValueChanged<Vec3> onChanged;
  final double step;

  const _Vec3Row({required this.label, required this.value, required this.onChanged, this.step = 0.1});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: T.hint),
          const SizedBox(height: 3),
          Row(
            children: [
              for (var a = 0; a < 3; a++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: a < 2 ? 4 : 0),
                    child: _NumField(
                      key: ValueKey('$label-$a-${value.axisValue(a)}'),
                      value: value.axisValue(a),
                      onChanged: (v) => onChanged(value.withAxis(a, v)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumField extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _NumField({super.key, required this.value, required this.onChanged});

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final TextEditingController _c =
      TextEditingController(text: widget.value.toStringAsFixed(2));
  final _focus = FocusNode();

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      focusNode: _focus,
      style: T.mono,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      onSubmitted: (v) {
        final d = double.tryParse(v);
        if (d != null) widget.onChanged(d);
      },
      onTapOutside: (_) => _focus.unfocus(),
    );
  }
}

// ---------- Material tab ----------

class _MaterialTab extends StatelessWidget {
  const _MaterialTab();

  static const palette = [
    0xFF8C97A3, 0xFFB3402E, 0xFFD9742B, 0xFFE0B33C, //
    0xFF5B9A4F, 0xFF2E8B84, 0xFF3D6FB4, 0xFF6B4FA0,
    0xFFB35A8C, 0xFF8A6A52, 0xFF3A3A40, 0xFFE8E6E1,
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final o = (app.mode == EditorMode.edit ? app.editObj : app.activeObj)!;
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        const PanelHeader(title: 'Base Color'),
        SizedBox(
          height: 64,
          child: GridView.count(
            crossAxisCount: 6,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            padding: const EdgeInsets.all(8),
            children: [
              for (final (i, c) in palette.indexed)
                InkWell(
                  key: ValueKey('swatch-$i'),
                  onTap: () => app.setActiveColor(Color(c)),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Color(c),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: o.material.color.toARGB32() == c ? Colors.white : T.border,
                        width: o.material.color.toARGB32() == c ? 2 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _SliderRow(label: 'Metallic', value: o.material.metallic, onChanged: app.setActiveMetallic),
        _SliderRow(label: 'Roughness', value: o.material.roughness, onChanged: app.setActiveRoughness),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _SliderRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 68, child: Text(label, style: T.hint)),
            Expanded(
              child: Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged),
            ),
            SizedBox(width: 34, child: Text(value.toStringAsFixed(2), style: T.mono)),
          ],
        ),
      );
}

// ---------- Modifiers tab ----------

class _ModifiersTab extends StatelessWidget {
  const _ModifiersTab();

  static const _types = {
    'mirror': 'Mirror',
    'array': 'Array',
    'subdivision': 'Subdivision Surface',
    'bevel': 'Bevel',
    'solidify': 'Solidify',
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final idx = app.mode == EditorMode.edit ? app.editTarget : app.activeObject;
    final o = (app.mode == EditorMode.edit ? app.editObj : app.activeObj)!;
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Row(
          children: [
            Expanded(
              child: _AddModifierButton(
                onPick: (t) => app.addModifier(t),
                types: _types,
              ),
            ),
            if (o.modifiers.isNotEmpty) ...[
              const SizedBox(width: 6),
              _SmallButton(label: 'Apply All', onTap: () => app.applyAllModifiers(idx!)),
            ],
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < o.modifiers.length; i++)
          _ModifierCard(objIdx: idx!, modIdx: i, mod: o.modifiers[i]),
        if (o.modifiers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No modifiers.\nAdd one above.', textAlign: TextAlign.center, style: T.hint),
          ),
      ],
    );
  }
}

class _AddModifierButton extends StatelessWidget {
  final ValueChanged<String> onPick;
  final Map<String, String> types;

  const _AddModifierButton({required this.onPick, required this.types});

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, child) => OutlinedButton.icon(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Add Modifier', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: T.text,
          padding: const EdgeInsets.symmetric(vertical: 10),
          side: const BorderSide(color: T.border),
        ),
      ),
      menuChildren: [
        for (final e in types.entries)
          MenuItemButton(
            onPressed: () => onPick(e.key),
            child: Text(e.value),
          ),
      ],
    );
  }
}

class _ModifierCard extends StatelessWidget {
  final int objIdx;
  final int modIdx;
  final MeshModifier mod;

  const _ModifierCard({required this.objIdx, required this.modIdx, required this.mod});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: T.panelAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: T.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 6),
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: mod.enabled,
                  onChanged: (v) {
                    mod.enabled = v ?? true;
                    app.refresh();
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  switch (mod.type) {
                    'mirror' => 'Mirror',
                    'array' => 'Array',
                    'subdivision' => 'Subdivision Surface',
                    'bevel' => 'Bevel',
                    _ => 'Solidify',
                  },
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              _iconBtn(Icons.arrow_upward, () => app.moveModifier(objIdx, modIdx, -1)),
              _iconBtn(Icons.arrow_downward, () => app.moveModifier(objIdx, modIdx, 1)),
              _iconBtn(Icons.check, () => app.applyModifier(objIdx, modIdx), tooltip: 'Apply'),
              _iconBtn(Icons.close, () => app.removeModifier(objIdx, modIdx)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: _ModifierSettings(mod: mod, onChanged: () => app.refresh()),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData i, VoidCallback onTap, {String? tooltip}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(i, size: 14, color: T.textDim),
        ),
      );
}

class _ModifierSettings extends StatelessWidget {
  final MeshModifier mod;
  final VoidCallback onChanged;

  const _ModifierSettings({required this.mod, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return switch (mod) {
      MirrorModifier m => Row(
          children: [
            for (var a = 0; a < 3; a++)
              _ToggleChip(
                label: 'XYZ'[a],
                active: m.axis == a,
                onTap: () {
                  m.axis = a;
                  onChanged();
                },
              ),
            const Spacer(),
            _ToggleChip(
              label: 'Merge',
              active: m.merge,
              onTap: () {
                m.merge = !m.merge;
                onChanged();
              },
            ),
          ],
        ),
      ArrayModifier m => Row(
          children: [
            Text('Count', style: T.hint),
            Expanded(
              child: Slider(
                value: m.count.toDouble(),
                min: 1,
                max: 12,
                divisions: 11,
                onChanged: (v) {
                  m.count = v.round();
                  onChanged();
                },
              ),
            ),
            Text('${m.count}', style: T.mono),
          ],
        ),
      SubdivisionModifier m => Row(
          children: [
            Text('Levels', style: T.hint),
            Expanded(
              child: Slider(
                value: m.levels.toDouble(),
                min: 0,
                max: 3,
                divisions: 3,
                onChanged: (v) {
                  m.levels = v.round();
                  onChanged();
                },
              ),
            ),
            Text('${m.levels}', style: T.mono),
          ],
        ),
      BevelModifier m => Row(
          children: [
            Text('Amount', style: T.hint),
            Expanded(
              child: Slider(
                value: m.amount,
                min: 0.02,
                max: 0.5,
                onChanged: (v) {
                  m.amount = v;
                  onChanged();
                },
              ),
            ),
            Text(m.amount.toStringAsFixed(2), style: T.mono),
          ],
        ),
      SolidifyModifier m => Row(
          children: [
            Text('Thickness', style: T.hint),
            Expanded(
              child: Slider(
                value: m.thickness.clamp(0.0, 1.0),
                min: 0.01,
                max: 1,
                onChanged: (v) {
                  m.thickness = v;
                  onChanged();
                },
              ),
            ),
            Text(m.thickness.toStringAsFixed(2), style: T.mono),
          ],
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToggleChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 4),
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

class _SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SmallButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: T.text,
          padding: const EdgeInsets.symmetric(vertical: 8),
          side: const BorderSide(color: T.border),
          textStyle: const TextStyle(fontSize: 11.5),
        ),
        child: Text(label),
      );
}
