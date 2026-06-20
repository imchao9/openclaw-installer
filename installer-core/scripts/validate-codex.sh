#!/usr/bin/env bash
# Validate Codex CLI only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_OPENCLAW=0 VALIDATE_CODEX=1 exec bash "$SCRIPT_DIR/validate-agent-configs.sh"
