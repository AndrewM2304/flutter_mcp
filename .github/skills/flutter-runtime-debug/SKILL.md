---
name: flutter-runtime-debug
description: Connect to a running local Flutter app through the in-house flutter-agent-runtime MCP server and debug app state, Riverpod updates, GoRouter navigation, Talker logs, network metadata, runtime errors, and widget rebuilds. Use when given a Flutter VM Service or DevTools URL, asked to run diagnostics, or asked why live runtime tracking is not visible in VS Code.
argument-hint: "[VM Service or DevTools URL] [workspace root]"
---

# Flutter Runtime Debug

This skill runs live diagnostics against the local `flutter_agent_runtime` MCP server. Follow the workflow in [MCP workflow](./references/mcp-workflow.md).

## Inputs

Collect these before calling MCP tools:

- `uri`: the Flutter VM Service URL or DevTools URL from `flutter run`.
- `workspace_root`: the app root, such as `/Users/andrewmiller/Development/mcp/examples/runtime_sample_app`.

If the user gives a DevTools URL, use it directly or normalize it to the base VM Service URL. Both forms are acceptable:

```text
http://127.0.0.1:49654/85TQl9gidoE=/
http://127.0.0.1:49654/85TQl9gidoE=/devtools/?uri=ws://127.0.0.1:49654/85TQl9gidoE=/ws
```

## Process

1. Call `connect_to_app` with `uri` and `workspace_root`.
2. Call `flutter_diagnostics_bundle` and use it as the main summary.
3. Call targeted tools only when useful:
   - `riverpod_state` for provider lifecycle, updates, and latest values.
   - `go_router_state` for route stack, current location, redirects, and route errors.
   - `app_logs` for structured Talker/runtime logs.
   - `network_requests` for metadata-only HTTP failures or slow calls.
   - `flutter_events` for raw recent runtime events by category.
4. For rebuild investigations, call `widget_rebuilds`. Ask the developer to interact with the app during the sample window if there is no UI activity.
5. If the developer says nothing appears in VS Code Output, call `mcp_activity_log` and reference `.dart_tool/flutter_agent_mcp_server.log`. Do not expect detailed app state to be printed to Output automatically.
6. Report findings with evidence and next actions. Include capability gaps when the app has not installed runtime instrumentation.

## Interpretation Rules

- Empty rebuild results can mean the app was idle during sampling, not that rebuild tracking is broken.
- Missing provider, route, log, or network sections usually means the corresponding adapter or forwarding call has not been wired into the app.
- MCP server stdout is protocol-only. Human-readable activity is in stderr when VS Code exposes it, and always in `.dart_tool/flutter_agent_mcp_server.log`.
- Network bodies are intentionally not captured. Do not ask for or infer request/response bodies from v1 diagnostics.

## Expected Output

Summarize:

- connection status and instrumentation capability status
- current route and notable navigation events
- provider count and recent suspicious provider changes
- latest runtime errors or failed network requests
- top rebuild hotspots with source locations when available
- concrete next debugging or code changes
