# Dash Client Onboarding

Use this checklist when wiring the Flutter agent runtime into a multi-repo app
such as dash client.

## 1. Clone Repos

Each developer needs:

- **Tooling repo** — MCP server, runtime packages, agents, skills
- **App repo** — dash client (or the sub-repo that owns the Flutter app)

## 2. Add Runtime Packages

In the app `pubspec.yaml`:

```yaml
dependencies:
  flutter_agent_runtime:
    path: <tooling-repo>/packages/flutter_agent_runtime
  flutter_agent_runtime_adapters:
    path: <tooling-repo>/packages/flutter_agent_runtime_adapters
```

Run `flutter pub get` in the app repo.

## 3. Wire Instrumentation

Follow [setup.md](setup.md) and the `flutter-runtime-integrate` skill:

- `AgentRuntime.init()` before `runApp`
- `AgentProviderObserver` on `ProviderScope`
- `AgentGoRouterObserver` on `GoRouter`
- `AgentTalkerObserver` on Talker (if used)
- `AgentNetworkObserver.recordRequest(...)` in the HTTP layer

Keep existing observers. Add agent observers alongside them.

## 4. Configure VS Code In The App Repo

From the tooling repo:

```bash
./tool/setup_vscode_for_app.sh /path/to/dash-client
```

Or copy [templates/app.mcp.json](templates/app.mcp.json) manually.

## 5. Start MCP Once Per Session

1. Open the **app repo** in VS Code
2. **MCP: List Servers** → start `flutter-agent-runtime`
3. Confirm `.dart_tool/flutter_agent_mcp_server.log` shows `received initialize request`

## 6. Debug With The Agent

Use the **Flutter Runtime Debugger** agent with:

```text
connect to <VM Service URI>
workspace_root: /absolute/path/to/dash-client
```

Prefer `connect_and_diagnose` or `flutter_diagnostics_bundle` for the first summary.

## 7. Validate

From the tooling repo:

```bash
./tool/validate.sh
dart tool/mcp_stdio_smoke.dart \
  --vm-service-uri "http://127.0.0.1:PORT/TOKEN=/" \
  --workspace-root "/path/to/dash-client"
```

## Common Mistakes

- Opening the tooling repo instead of the app repo when debugging dash client
- Using a relative `packages/flutter_agent_mcp_server/...` path in app MCP config
- Pressing Skip when MCP loading stalls — fix startup instead
- Using Dart SDK MCP tools instead of `flutter-agent-runtime`
- Reporting provider defaults from source instead of `currentProviders`

See [troubleshooting_vscode_mcp.md](troubleshooting_vscode_mcp.md) for MCP startup issues.
