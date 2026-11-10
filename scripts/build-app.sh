#!/bin/bash
# Builds Islet.app (universal, ad-hoc signed) and a zip for GitHub Releases.
# Works with Xcode or with the Command Line Tools only — no paid account.
#
#   ./scripts/build-app.sh            # release build into ./dist
#   ISLET_ARCHS="arm64" ./scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="${ISLET_VERSION:-$(cat VERSION)}"
ARCHS="${ISLET_ARCHS:-arm64 x86_64}"
MIN_MACOS="14.0"
BUILD="$ROOT/.build/app"
DIST="$ROOT/dist"
APP="$DIST/Islet.app"

rm -rf "$BUILD" "$APP"
mkdir -p "$BUILD" "$DIST"

# Some Command Line Tools 16.x installs ship a duplicate SwiftBridging
# module map that breaks every `import Foundation`. Hide it via a VFS overlay
# (no system files are touched). Harmless on healthy toolchains.
VFS_FLAGS=()
DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
DUP_MAP="$DEV_DIR/usr/include/swift/module.modulemap"
if [[ "$DEV_DIR" == *CommandLineTools* && -f "$DUP_MAP" ]]; then
  : > "$BUILD/empty.modulemap"
  cat > "$BUILD/overlay.yaml" <<EOF
{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "directory", "name": "$DEV_DIR/usr/include/swift", "contents": [ { "type": "file", "name": "module.modulemap", "external-contents": "$BUILD/empty.modulemap" } ] } ] }
EOF
  VFS_FLAGS=(-vfsoverlay "$BUILD/overlay.yaml" -Xcc -ivfsoverlay -Xcc "$BUILD/overlay.yaml")
fi

SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(find Sources/Islet -name '*.swift' | sort)

BINARIES=()
for arch in $ARCHS; do
  echo "→ compiling $arch"
  swiftc ${VFS_FLAGS[@]+"${VFS_FLAGS[@]}"} -parse-as-library -swift-version 5 -O -whole-module-optimization \
    -target "$arch-apple-macos$MIN_MACOS" \
    "${SOURCES[@]}" -o "$BUILD/Islet-$arch"
  BINARIES+=("$BUILD/Islet-$arch")
done

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Islet"
cp Sources/Islet/Resources/Localizable.xcstrings "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__MIN_MACOS__/$MIN_MACOS/g" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature: no Developer ID, no notarization (see README → Gatekeeper).
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

ZIP="$DIST/Islet-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "✓ $APP"
echo "✓ $ZIP"
