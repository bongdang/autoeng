#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
signing_directory="$project_root/.local-signing"
certificate="$signing_directory/certificate.pem"
expected_identity="$(cat "$signing_directory/identity.sha1")"
actual_identity="$(openssl x509 -in "$certificate" -noout -fingerprint -sha1 | sed 's/.*=//;s/://g')"
if [ "$expected_identity" != "$actual_identity" ]; then
    echo 'FAIL: certificate does not match the saved local signing identity.' >&2
    exit 1
fi
# User domain only, code signing policy only, /usr/bin/codesign application only.
# Does not trust this certificate for TLS, mail, or the system/admin trust domain.
security add-trusted-cert -r trustRoot -p codeSign -a /usr/bin/codesign \
    -k "$signing_directory/autoeng.keychain-db" "$certificate"
echo 'Enabled user trust for this certificate only for the codesign tool and code signing policy.'
