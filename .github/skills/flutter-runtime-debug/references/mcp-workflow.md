# MCP Workflow Reference

## Start Sequence

1. Confirm the Flutter app is running in debug mode.
2. Copy the VM Service URL printed by Flutter. A DevTools URL is also acceptable.
3. Confirm `.vscode/mcp.json` starts the server directly:

```json
{
  "servers": {
    "flutter-agent-runtime": {
      "command": "dart",
      "args": [
        "packages/flutter_agent_mcp_server/bin/flutter_agent_mcp_server.dart"
      ]
    }
  }
}
```

Do not configure the MCP server as `dart run flutter_agent_mcp_server`; package build messages on stdout can break stdio MCP initialization.

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
