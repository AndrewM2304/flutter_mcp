# MCP Workflow Reference

## Start Sequence

1. Confirm the current workspace is the Flutter app repo or app sub-repo being
   debugged. Use this path as `workspace_root`.
2. Confirm the Flutter app is running in debug mode.
3. Copy the VM Service URL printed by Flutter. A DevTools URL is also acceptable.
4. Confirm the current app repo's MCP config starts the server directly from
   the external tooling repo:

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

Do not configure the MCP server as `dart run flutter_agent_mcp_server`; package build messages on stdout can break stdio MCP initialization.

If the agent cannot see the MCP tools, report that the current app workspace
does not have the `flutter-agent-runtime` server available and ask for the app
repo MCP config to be reloaded.

## Tool Order

Use this order for a full pass:

```text
connect_to_app
get_app_info
flutter_diagnostics_bundle
riverpod_state
go_router_state
app_logs
network_requests
widget_rebuilds
mcp_activity_log
```

Use `flutter_diagnostics_bundle` again after rebuild sampling or after the developer reproduces an issue.

## Bug Tracking Loop

For each suspected bug:

1. Capture the route or screen where the user reproduced it.
2. Capture recent provider, log, error, and network events.
3. Capture rebuild data only when the issue is visual stutter, excessive work,
   or stale UI.
4. Map runtime facts back to app repo files, symbols, providers, and routes.
5. State confidence and remaining gaps before recommending code changes.

## Rebuild Sampling

`widget_rebuilds` enables Flutter inspector rebuild tracking temporarily. If the result is empty:

- ask the developer to interact with the app during the sample
- retry with a longer sample if supported by tool arguments
- check whether the app is a debug build with Flutter inspector extensions available

## Visibility

VS Code Output may only show MCP Gateway connection messages. Detailed runtime data is returned to the agent through MCP tools. Server-side activity is available through:

```text
.dart_tool/flutter_agent_mcp_server.log
```

and through the `mcp_activity_log` tool.

The log file location is relative to the MCP server process working directory,
which may be the app repo or the agent client's configured cwd.
