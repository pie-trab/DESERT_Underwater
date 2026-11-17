#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PYTHON=${PYTHON:-python3}

"$PYTHON" -m py_compile "$HERE"/*.py
PYTHONPATH="$HERE" "$PYTHON" "$HERE/check.py"
