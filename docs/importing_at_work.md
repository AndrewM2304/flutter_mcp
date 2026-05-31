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

Point VS Code at the external agent/skills repo from the app workspace. Add
[work.vscode.settings.json](templates/work.vscode.settings.json) to the app
repo `.vscode/settings.json`, adjusting the paths for each developer machine.
Alternatively, copy the agent and skills folders into the user profile:

```text
~/.copilot/agents
~/.copilot/skills
```

## MCP Client Config

Configure the app repo agent client to run the launcher script from the tooling
repo. Copy [app.mcp.json](templates/app.mcp.json) into the app repo as
`.vscode/mcp.json`. The first start prompts for the tooling repo path on that
machine.

For the tooling repo itself, `.vscode/mcp.json` uses the launcher relative to
`${workspaceFolder}`.

```json
{
  "servers": {
    "flutter-agent-runtime": {
      "type": "stdio",
      "command": "/bin/bash",
      "args": [
        "<path-to-tooling-repo>/tool/start_flutter_agent_mcp_server.sh"
      ]
    }
  }
}
```

Avoid `dart run flutter_agent_mcp_server` for MCP config because package build
messages can write to stdout before the MCP protocol starts.

If VS Code hangs while loading the MCP server, see
[troubleshooting_vscode_mcp.md](troubleshooting_vscode_mcp.md).

For app repo setup, run:

```bash
./tool/setup_vscode_for_app.sh /path/to/app-repo
```

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

