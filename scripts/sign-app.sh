#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
exec /usr/bin/python3 "$project_root/scripts/sign_app.py" "$@"
