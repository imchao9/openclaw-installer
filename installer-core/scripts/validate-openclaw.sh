#!/usr/bin/env bash
# Validate OpenClaw CLI/model reply only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_OPENCLAW=1 VALIDATE_CODEX=0 exec bash "$SCRIPT_DIR/validate-agent-configs.sh"
