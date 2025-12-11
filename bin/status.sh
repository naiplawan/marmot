#!/bin/bash
# Entry point for the Go-based system status panel bundled with Marmarmott.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO_BIN="$SCRIPT_DIR/status-go"
if [[ -x "$GO_BIN" ]]; then
    exec "$GO_BIN" "$@"
fi

echo "Bundled status binary not found. Please reinstall marmot or run marmot update to restore it." >&2
exit 1
