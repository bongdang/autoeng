#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
# Some CLT SwiftPM versions do not discover the bundled Testing macro plugin.
# Use the plugin belonging to the currently selected toolchain when available.
swiftc_path="$(xcrun --find swiftc)"
plugin_path="$(dirname "$swiftc_path")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ -f "$plugin_path" ]; then
    exec swift test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$plugin_path" "$@"
else
    exec swift test --disable-xctest "$@"
fi
