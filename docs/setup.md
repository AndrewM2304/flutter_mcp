# Setup

## App Dependencies

Add the runtime and adapters packages to the Flutter app under development:

```yaml
dependencies:
  flutter_agent_runtime:
    path: <path-to-tooling-repo>/packages/flutter_agent_runtime
  flutter_agent_runtime_adapters:
    path: <path-to-tooling-repo>/packages/flutter_agent_runtime_adapters
```

Use the relative path that matches the app repository layout.

In a multi-repo setup, keep `flutter_agent_mcp_server` in the developer tooling
repo or add it only as a dev dependency in the agent/client workspace. The app
only needs `flutter_agent_runtime` and optional adapters for debug
instrumentation.

## App Bootstrap

Initialize the runtime before `runApp` and install error hooks in debug builds:

```dart
void main() {
  AgentRuntime.init();
  AgentRuntime.installErrorHooks();

  runApp(ProviderScope(
    observers: [
      existingRiverpodObserver,
      const AgentProviderObserver(),
    ],
    child: const App(),
  ));
}
```

`AgentRuntime.installErrorHooks()` preserves and forwards to existing Flutter and platform error handlers by default.

## GoRouter

Add the agent route observer next to existing Talker or app observers:

```dart
final agentRouteObserver = AgentGoRouterObserver();

final router = GoRouter(
  observers: [
    existingTalkerRouteObserver,
    agentRouteObserver,
  ],
  redirect: (context, state) {
    final target = computeRedirect(state);
    if (target != null) {
      agentRouteObserver.recordGoRouterRedirect(
        state: state,
        targetLocation: target,
        reason: 'auth',
      );
    }
    return target;
  },
  routes: routes,
);
```

## Talker

Add `AgentTalkerObserver` to the same Talker instance that the app already uses. If the app already has one Talker observer, create a small composite observer that forwards to both observers.

```dart
final talker = Talker(
  observer: const AgentTalkerObserver(),
);
```

## MCP

Start the app in Flutter debug mode, then connect the MCP server with the app VM Service URI:

```json
{
  "name": "connect_to_app",
  "arguments": {
    "uri": "http://127.0.0.1:XXXXX/...",
    "workspace_root": "/absolute/path/to/flutter/app"
  }
}
```

For agents, the first diagnostic tool should usually be `flutter_diagnostics_bundle`.

## MCP Client Configuration

When configuring an agent client from a different repo, point the command at
the tooling repo launcher script:

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

Copy [templates/app.mcp.json](templates/app.mcp.json) into the app repo as
`.vscode/mcp.json` to prompt once per machine for the tooling repo path.

Prefer this launcher over a bare `dart <script>` path from the app repo. VS Code
starts MCP servers with the app workspace as the working directory, so relative
`packages/...` paths will not resolve.

Avoid `dart run flutter_agent_mcp_server` for MCP config because package build
messages can write to stdout before the MCP protocol starts.

If VS Code hangs while loading the MCP server, see
[troubleshooting_vscode_mcp.md](troubleshooting_vscode_mcp.md).

## Validation

From the tooling repo root:

```bash
./tool/validate.sh
dart tool/mcp_stdio_smoke.dart
```

For a live app smoke test, start the Flutter app in debug mode, copy the VM
Service URI, then run:

```bash
dart tool/mcp_stdio_smoke.dart \
  --vm-service-uri "http://127.0.0.1:XXXXX/abc123=/" \
  --workspace-root "<absolute-path-to-flutter-app-repo>"
```
