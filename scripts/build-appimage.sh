#!/usr/bin/env bash
# Package a Flutter Linux bundle as an AppImage using appimagetool.
#
# Usage: scripts/build-appimage.sh <bundle-dir> <output-file> [arch]
#   arch: x86_64 or aarch64 (default x86_64)
set -euo pipefail

BUNDLE_DIR="${1:?usage: build-appimage.sh <bundle-dir> <output-file> [arch]}"
OUT="${2:?usage: build-appimage.sh <bundle-dir> <output-file> [arch]}"
ARCH="${3:-x86_64}"

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "build-appimage: bundle dir not found: $BUNDLE_DIR" >&2
  exit 1
fi

case "$ARCH" in
  x86_64) TOOL_ARCH="x86_64" ;;
  aarch64|arm64) TOOL_ARCH="aarch64" ;;
  *) echo "build-appimage: unsupported arch: $ARCH" >&2; exit 1 ;;
esac

APPDIR="$(mktemp -d)/toaster.AppDir"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/icons/hicolor/256x256/apps"

cp -a "$BUNDLE_DIR/." "$APPDIR/usr/bin/"
cp "$(dirname "${BASH_SOURCE[0]}")/../assets/icon-1024.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/toaster.png"

cat > "$APPDIR/toaster.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=toaster
Comment=A pocket-sized Blender-style 3D modeler
Exec=toaster
Icon=toaster
Categories=Graphics;3DGraphics;
Terminal=false
EOF

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
exec "$(dirname "$0")/usr/bin/toaster" "$@"
EOF
chmod +x "$APPDIR/AppRun"
ln -sf usr/share/icons/hicolor/256x256/apps/toaster.png "$APPDIR/toaster.png"
ln -sf toaster.png "$APPDIR/.DirIcon"

TOOL="/tmp/appimagetool-$TOOL_ARCH.AppImage"
if [ ! -x "$TOOL" ]; then
  curl -fsSL --retry 3 -o "$TOOL" \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$TOOL_ARCH.AppImage"
  chmod +x "$TOOL"
fi

ARCH="$TOOL_ARCH" "$TOOL" "$APPDIR" "$OUT"
echo "build-appimage: $OUT"
