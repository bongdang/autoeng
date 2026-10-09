#!/bin/bash
set -euo pipefail
umask 077
project_root="$(cd "$(dirname "$0")/.." && pwd)"
signing_directory="$project_root/.local-signing"
keychain_path="$signing_directory/autoeng.keychain-db"
if [ -f "$signing_directory/identity.sha1" ]; then
    echo 'Local signing identity already exists; keeping it unchanged.'
    exit 0
fi
if [ -d "$signing_directory" ] && [ -n "$(ls -A "$signing_directory")" ]; then
    echo 'FAIL: incomplete local signing setup; existing files were preserved.' >&2
    exit 1
fi
mkdir -p "$signing_directory"
chmod 700 "$signing_directory"
private_key="$signing_directory/import-private-key.pem"
identity_archive="$signing_directory/import-identity.p12"
cleanup() {
    rm -f "$private_key" "$identity_archive"
    # Do not leave this project-only keychain in the user's normal search list.
    local paths=() line path removed=0
    while IFS= read -r line; do
        path="${line#*\"}"; path="${path%\"*}"
        if [ "$path" = "$keychain_path" ]; then removed=1
        else paths+=("$path"); fi
    done < <(security list-keychains -d user)
    if [ "$removed" = 1 ]; then security list-keychains -d user -s "${paths[@]}"; fi
    security lock-keychain "$keychain_path" >/dev/null 2>&1 || true
}
trap cleanup EXIT
openssl rand -hex 32 > "$signing_directory/password"
keychain_password="$(cat "$signing_directory/password")"
openssl req -new -newkey rsa:3072 -nodes -x509 -days 3650 -sha256 \
    -config "$project_root/Resources/local-signing.cnf" \
    -keyout "$private_key" -out "$signing_directory/certificate.pem" \
    > "$signing_directory/generation.log" 2>&1
openssl pkcs12 -export -inkey "$private_key" -in "$signing_directory/certificate.pem" \
    -name 'Autoeng Local Development' -out "$identity_archive" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout "file:$signing_directory/password"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 3600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$identity_archive" -k "$keychain_path" -P "$keychain_password" -x -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S 'apple-tool:,apple:' -s -k "$keychain_password" "$keychain_path" >/dev/null
openssl x509 -in "$signing_directory/certificate.pem" -noout -fingerprint -sha1 \
    | sed 's/.*=//;s/://g' > "$signing_directory/identity.sha1"
echo 'Created a project-only code signing identity. No system trust settings were changed.'
echo 'Next: ./scripts/trust-local-signing.sh (user code-signing trust scoped to /usr/bin/codesign).'
