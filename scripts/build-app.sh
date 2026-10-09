#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
configuration="${1:-debug}"
case "$configuration" in
    debug|release) ;;
    *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;;
esac

ensure_stopped() {
    local status
    if pgrep -x Autoeng >/dev/null; then
        echo "Autoeng is running. Quit it from the menu before building." >&2
        exit 2
    else
        status=$?
        if [[ "$status" != 1 ]]; then
            echo "Cannot determine whether Autoeng is running; bundle left unchanged." >&2
            exit 2
        fi
    fi
}
ensure_stopped
swift build --configuration "$configuration" --product Autoeng
binary_path="$(swift build --configuration "$configuration" --show-bin-path)"
bundle_path="$project_root/build/Autoeng.app"
mkdir -p "$project_root/build"
staging="$(mktemp -d "$project_root/build/package.XXXXXX")"
cleanup() {
    if [[ -e "$staging/previous.app" ]]; then
        echo "Previous bundle preserved at: $staging/previous.app" >&2
    else
        rm -rf "$staging"
    fi
}
trap cleanup EXIT
candidate="$staging/Autoeng.app"
mkdir -p "$candidate/Contents/MacOS"
cp "$binary_path/Autoeng" "$candidate/Contents/MacOS/Autoeng"
cp Resources/Info.plist "$candidate/Contents/Info.plist"
plutil -lint "$candidate/Contents/Info.plist"
./scripts/sign-app.sh "$candidate"
ensure_stopped
if [[ -e "$bundle_path" ]]; then
    mv "$bundle_path" "$staging/previous.app"
fi
if ! mv "$candidate" "$bundle_path"; then
    if [[ -e "$staging/previous.app" ]]; then
        mv "$staging/previous.app" "$bundle_path" || true
    fi
    exit 1
fi
rm -rf "$staging/previous.app"
echo "Built: $bundle_path"
