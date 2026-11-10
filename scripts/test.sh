#!/bin/bash
# Runs the unit tests.
#  • With a working SwiftPM (Xcode / healthy toolchain): `swift test`.
#  • Otherwise (e.g. broken Command Line Tools): compiles app sources + tests
#    into one binary and runs it with the Swift Testing entry point.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${ISLET_FORCE_LOCAL:-0}" != "1" ]] && swift package describe >/dev/null 2>&1; then
  exec swift test
fi

BUILD=".build/localtests"
mkdir -p "$BUILD"
DEV_DIR="$(xcode-select -p)"
FW="$DEV_DIR/Library/Developer/Frameworks"
VFS_FLAGS=()
if [[ "$DEV_DIR" == *CommandLineTools* && -f "$DEV_DIR/usr/include/swift/module.modulemap" ]]; then
  : > "$BUILD/empty.modulemap"
  cat > "$BUILD/overlay.yaml" <<EOF
{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "directory", "name": "$DEV_DIR/usr/include/swift", "contents": [ { "type": "file", "name": "module.modulemap", "external-contents": "$PWD/$BUILD/empty.modulemap" } ] } ] }
EOF
  VFS_FLAGS=(-vfsoverlay "$BUILD/overlay.yaml" -Xcc -ivfsoverlay -Xcc "$BUILD/overlay.yaml")
fi

cat > "$BUILD/Runner.swift" <<'EOF'
import Foundation
import Testing
@main struct LocalTestRunner {
    static func main() async {
        let code: CInt = await Testing.__swiftPMEntryPoint(passing: nil)
        exit(code)
    }
}
EOF

SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(find Sources/Islet -name '*.swift' ! -name 'Main.swift' | sort)
while IFS= read -r f; do SOURCES+=("$f"); done < <(find Tests/IsletTests -name '*.swift' | sort)

swiftc ${VFS_FLAGS[@]+"${VFS_FLAGS[@]}"} -parse-as-library -swift-version 5 -Onone -D ISLET_LOCAL_TESTS \
  -target "$(uname -m)-apple-macos14.0" -module-name IsletLocalTests \
  -F "$FW" -framework Testing -Xlinker -rpath -Xlinker "$FW" \
  "${SOURCES[@]}" "$BUILD/Runner.swift" -o "$BUILD/run-tests"
"$BUILD/run-tests" "$@"
