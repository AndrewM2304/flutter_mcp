#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run() {
  echo
  echo "==> $*"
  "$@"
}

run dart analyze "$repo_root"

(
  cd "$repo_root/packages/flutter_agent_mcp_server"
  run dart test
)

run flutter analyze "$repo_root/packages/flutter_agent_runtime"

(
  cd "$repo_root/packages/flutter_agent_runtime"
  run flutter test
)

run flutter analyze "$repo_root/packages/flutter_agent_runtime_adapters"
run flutter analyze "$repo_root/examples/runtime_sample_app"

(
  cd "$repo_root/examples/runtime_sample_app"
  run flutter test
)

