# Importing Into Work Repos

This project is intended to split cleanly across a multi-repo setup.

## Tooling Repo

Keep these packages together in the MCP/tooling repo:

```text
packages/flutter_agent_mcp_server
packages/flutter_agent_runtime
packages/flutter_agent_runtime_adapters
tool
docs
```

The MCP server is developer tooling. It should be launched by the agent client
over stdio and does not need to be imported by the Flutter app that ships to
users.

## App Repo

The Flutter app repo imports only the debug runtime packages:

```yaml
dependencies:
  flutter_agent_runtime:
    path: <path-to-tooling-repo>/packages/flutter_agent_runtime
  flutter_agent_runtime_adapters:
    path: <path-to-tooling-repo>/packages/flutter_agent_runtime_adapters
```

If the app does not use Riverpod, GoRouter, or Talker, omit
`flutter_agent_runtime_adapters` and call `AgentRuntime.instance` directly from
the app's existing debug instrumentation points.

Initialize the runtime only from debug/development bootstrap code. The package
also no-ops in release mode, but keeping integration behind the app's existing
debug entrypoint makes intent obvious during review.

## Agent And Skills Repo

Copy or vendor these files into the agent/skills repo:

```text
.github/agents/flutter-runtime-debugger.agent.md
.github/skills/flutter-runtime-debug
.github/skills/flutter-runtime-integrate
```

Keep the skill references generic. Do not add machine-specific absolute paths
to checked-in agent or skill files.

## MCP Client Config

Configure the agent client to run the server script directly:

```json
{
  "servers": {
    "flutter-agent-runtime": {
      "command": "dart",
      "args": [
        "<path-to-tooling-repo>/packages/flutter_agent_mcp_server/bin/flutter_agent_mcp_server.dart"
      ]
    }
  }
}
```

Avoid `dart run flutter_agent_mcp_server` for MCP config because package build
messages can write to stdout before the MCP protocol starts.

## Validation Before Import

From the tooling repo root:

```bash
./tool/validate.sh
dart tool/mcp_stdio_smoke.dart
```

For a live app validation:

```bash
dart tool/mcp_stdio_smoke.dart \
  --vm-service-uri "http://127.0.0.1:XXXXX/abc123=/" \
  --workspace-root "<absolute-path-to-flutter-app-repo>"
```

The live smoke test should report successful `connect_to_app` and
`flutter_diagnostics_bundle` calls. Missing instrumentation is a valid result
only when the app has not yet imported and initialized `flutter_agent_runtime`.

