---
name: flutter-runtime-debug
description: Connect to a running local Flutter app through the in-house flutter-agent-runtime MCP server and debug app state, Riverpod updates, GoRouter navigation, Talker logs, network metadata, runtime errors, and widget rebuilds. Use when given a Flutter VM Service or DevTools URL, asked to run diagnostics, or asked why live runtime tracking is not visible in VS Code.
argument-hint: "[VM Service or DevTools URL] [workspace root]"
---

# Flutter Runtime Debug

This skill runs live diagnostics from the current Flutter app repo or app
sub-repo against the `flutter_agent_runtime` MCP server. The MCP server may live
in a separate tooling repo and should be exposed to the current agent session as
`flutter-agent-runtime`. Follow the workflow in
[MCP workflow](./references/mcp-workflow.md) and read output using
[diagnostics shape](./references/diagnostics-shape.md).

## Inputs

Collect these before calling MCP tools:

- `uri`: the Flutter VM Service URL or DevTools URL from `flutter run`.
- `workspace_root`: the absolute path to the Flutter app repo or sub-repo being
  debugged. Do not use the MCP tooling repo path unless that is also the app
  under test.

If the user gives a DevTools URL, use it directly or normalize it to the base VM Service URL. Both forms are acceptable:

```text
http://127.0.0.1:49654/85TQl9gidoE=/
http://127.0.0.1:49654/85TQl9gidoE=/devtools/?uri=ws://127.0.0.1:49654/85TQl9gidoE=/ws
```

## Process

1. Confirm the `flutter-agent-runtime` MCP tools are available. If not, ask the
   developer to start the server from **MCP: List Servers**. Do not substitute
   Dart SDK MCP tools after Skip.
2. Prefer `connect_and_diagnose` with `summary: true` for the first pass.
3. Otherwise call `connect_to_app`, then immediately call
   `flutter_diagnostics_bundle`.
4. Read `currentProviders` and `currentRoute` before any other runtime tool.
5. Call targeted tools only when useful:
   - `riverpod_state` for provider lifecycle history
   - `go_router_state` for navigation history
   - `app_logs` for structured Talker/runtime logs
   - `network_requests` for metadata-only HTTP failures or slow calls
   - `flutter_events` for raw recent runtime events by category
6. For rebuild investigations, call `widget_rebuilds`. Ask the developer to
   interact with the app during the sample window if there is no UI activity.
7. If MCP output is unclear, call `mcp_activity_log`.
8. Use `reconnect_last` only when the MCP server is still running and the app
   was restarted with a new VM Service URI not yet provided by the developer.

## Issue Playbooks

### Provider value looks wrong

```text
connect_and_diagnose (summary=true)
riverpod_state
app_logs
```

Report `currentProviders.<name>.value` as the live value.

### Route/navigation issue

```text
connect_and_diagnose (summary=true)
go_router_state
flutter_events (type=route)
```

### Network failure

```text
connect_and_diagnose (summary=true)
network_requests
app_logs
```

### Rebuild/performance concern

```text
connect_and_diagnose (summary=true)
widget_rebuilds
flutter_diagnostics_bundle
```

Ask the developer to interact with the UI during `widget_rebuilds`.

## Interpretation Rules

- Do not use Dart Tooling Daemon, Widget Inspector, Flutter Driver, or source
  code to infer live provider values when `flutter-agent-runtime` should be used.
- Do not call `flutter_status` or `flutter_events` before `flutter_diagnostics_bundle`.
- Empty rebuild results can mean the app was idle during sampling.
- Missing provider, route, log, or network sections usually means missing adapters.
- Network bodies are intentionally not captured.

## Expected Output

Use this template:

1. **Connection** — connected, instrumentation present or missing
2. **Current route** — from `currentRoute`
3. **Current providers** — from `currentProviders`
4. **Recent issues** — errors, failed network, suspicious logs
5. **Next step** — one concrete follow-up
