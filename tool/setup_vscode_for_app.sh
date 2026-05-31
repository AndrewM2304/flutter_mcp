#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  tool/setup_vscode_for_app.sh <app-repo-path> [tooling-repo-path]

Writes VS Code MCP and agent settings into the app repo:
  <app-repo>/.vscode/mcp.json
  <app-repo>/.vscode/settings.json

If tooling-repo-path is omitted, it defaults to this repo's root.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 1 ]]; then
  usage
  exit 0
fi

app_root="$(cd "$1" && pwd)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tooling_root="$(cd "${2:-$script_dir/..}" && pwd)"
vscode_dir="$app_root/.vscode"

mkdir -p "$vscode_dir"

cat >"$vscode_dir/mcp.json" <<EOF
{
  "servers": {
    "flutter-agent-runtime": {
      "type": "stdio",
      "command": "dart",
      "args": [
        "$tooling_root/packages/flutter_agent_mcp_server/bin/flutter_agent_mcp_server.dart"
      ],
      "env": {
        "PATH": "\${env:HOME}/Development/flutter/bin:/opt/homebrew/bin:/usr/local/bin:\${env:PATH}"
      }
    }
  }
}
EOF

cat >"$vscode_dir/settings.json" <<EOF
{
  "chat.mcp.autostart": "never",
  "chat.agentFilesLocations": [
    "$tooling_root/.github/agents"
  ],
  "chat.agentSkillsLocations": [
    "$tooling_root/.github/skills"
  ]
}
EOF

echo "Wrote $vscode_dir/mcp.json"
echo "Wrote $vscode_dir/settings.json"
echo
echo "Next steps:"
echo "  1. Open $app_root in VS Code"
echo "  2. Run MCP: List Servers and start flutter-agent-runtime"
echo "  3. Use the Flutter Runtime Debugger agent with your VM Service URI"
