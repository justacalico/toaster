# toaster

Flutter 3.44.6, Dart 3.12.2. Pure-Dart software 3D renderer — no GPU or
platform channels needed to run or test.

## Commands

```bash
flutter pub get
flutter analyze
flutter test            # all tests, incl. widget tests + goldens
flutter test --coverage # writes coverage/lcov.info; gate is 100% lines
flutter test --update-goldens   # regenerate test/goldens/*.png
cog check               # validate conventional commits
cog bump --auto         # version bump + CHANGELOG + tag (CI does this)
```

## Layout

- `lib/core/` engine: `vec3` (Vec3/Mat4), `mesh`, `primitives`, `ops`
  (extrude/inset/subdivide/fill/delete), `modifiers`, `camera`,
  `picking`, `renderer` (produces RenderFrame), `scene`, `serializer`,
  `undo`, `file_store` (conditional io/web impl).
- `lib/app_state.dart` single ChangeNotifier above MaterialApp; UI reads
  via `context.watch`.
- `lib/ui/` shell (adaptive wide/compact at 820px), viewport, gizmo
  painter, toolbar, outliner, panels, menus, dialogs, status bar, theme.

## Rules

- Commits: Conventional Commits, `type: 中文描述`.
- Tests required for new behavior; keep coverage at 100%.
- Never commit `android/key.properties` or `*.jks` (signing lives in CI
  secrets; local fallback is debug signing).
