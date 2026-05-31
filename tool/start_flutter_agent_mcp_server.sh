#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tooling_root="$(cd "$script_dir/.." && pwd)"
server_script="$tooling_root/packages/flutter_agent_mcp_server/bin/flutter_agent_mcp_server.dart"

if [[ ! -f "$server_script" ]]; then
  echo "flutter_agent_mcp_server script not found at $server_script" >&2
  exit 1
fi

if [[ -n "${FLUTTER_AGENT_DART:-}" ]]; then
  dart_cmd="$FLUTTER_AGENT_DART"
elif [[ -x "${HOME}/Development/flutter/bin/dart" ]]; then
  dart_cmd="${HOME}/Development/flutter/bin/dart"
elif command -v dart >/dev/null 2>&1; then
  dart_cmd="$(command -v dart)"
else
  echo "dart executable not found. Set FLUTTER_AGENT_DART or add Flutter to PATH." >&2
  exit 1
fi

exec "$dart_cmd" "$server_script"
