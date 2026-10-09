#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
test_directory="$(mktemp -d "$project_root/build/signing-test.XXXXXX")"
# Only remove the isolated directory this test just created.
trap 'rm -rf "$test_directory"' EXIT
test_bundle="$test_directory/Autoeng.app"
ditto build/Autoeng.app "$test_bundle"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 1' "$test_bundle/Contents/Info.plist"
./scripts/sign-app.sh "$test_bundle"
first_requirement="$(codesign -d -r- "$test_bundle" 2>&1 | sed -n 's/^#\{0,1\} *designated => //p')"
first_hash="$(codesign -d --verbose=4 "$test_bundle" 2>&1 | sed -n 's/^CDHash=//p')"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 2' "$test_bundle/Contents/Info.plist"
./scripts/sign-app.sh "$test_bundle"
second_requirement="$(codesign -d -r- "$test_bundle" 2>&1 | sed -n 's/^#\{0,1\} *designated => //p')"
second_hash="$(codesign -d --verbose=4 "$test_bundle" 2>&1 | sed -n 's/^CDHash=//p')"
if [ -z "$first_requirement" ] || [ "$first_requirement" != "$second_requirement" ]; then
    echo 'FAIL: designated requirement changed between app versions' >&2
    exit 1
fi
if [ "$first_hash" = "$second_hash" ]; then
    echo 'FAIL: test did not change the signed app content' >&2
    exit 1
fi
codesign --verify --strict --test-requirement "=$first_requirement" "$test_bundle"
echo 'PASS: changed app content retains the same designated requirement and satisfies the previous requirement'
