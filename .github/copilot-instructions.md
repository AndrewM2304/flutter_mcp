# Flutter Agent Runtime MCP

When debugging a running Flutter app in this repo, use the **`flutter-agent-runtime` MCP server** only.

## Required MCP tools

Preferred first call:

```text
connect_and_diagnose
```

Otherwise:

1. `connect_to_app` with the VM Service URI and the app `workspace_root`
2. `flutter_diagnostics_bundle` for the first summary (`currentProviders`, route, logs, errors)
3. `riverpod_state`, `go_router_state`, `app_logs`, or `network_requests` when drilling down

Read [diagnostics-shape.md](../skills/flutter-runtime-debug/references/diagnostics-shape.md) for field paths.

## Do not use these substitutes

Do **not** use Dart SDK MCP tools for this workflow:

- Dart Tooling Daemon (`listDtdUris`, `connect`)
- Widget Inspector (`get_widget_tree`)
- Flutter Driver (`get_health`)
- Get runtime errors from the Dart SDK MCP server

Those tools do not expose Riverpod provider values, GoRouter agent events, Talker logs, or agent runtime network metadata.

## Do not guess live state

Never report provider values, routes, or counters from source code, widget trees, or defaults such as `StateProvider((ref) => 0)`. Read live values from `flutter_diagnostics_bundle` or `riverpod_state` after `connect_to_app`.

## If MCP startup stalls

If chat shows `Starting MCP servers flutter-agent-runtime... Skip?`, do not continue with substitute tools after Skip. Ask the developer to:

1. Run **MCP: List Servers** and start `flutter-agent-runtime` manually
2. Confirm `.dart_tool/flutter_agent_mcp_server.log` shows `received initialize request`
3. See [docs/troubleshooting_vscode_mcp.md](../docs/troubleshooting_vscode_mcp.md)

Do not start `flutter_agent_mcp_server.dart` manually in a terminal.

## Sample app workspace root

When debugging `examples/runtime_sample_app`, use:

```text
${workspaceFolder}/examples/runtime_sample_app
```

as `workspace_root`, not the tooling repo root.
