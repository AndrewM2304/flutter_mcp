---
name: flutter-runtime-integrate
description: Add or update in-house flutter_agent_runtime integration in a Flutter app, including runtime initialization, Riverpod ProviderObserver forwarding, GoRouter observer and redirect forwarding, Talker observer forwarding, and metadata-only network request recording. Use when asked to wire the runtime into an app or update existing observer data shapes.
argument-hint: "[Flutter app path]"
---

# Flutter Runtime Integration

This skill updates app repo or app sub-repo code so agents can inspect runtime
state through the external `flutter-agent-runtime` MCP server. Follow
[observer shape guidance](./references/observer-shapes.md) and keep all
existing observers working.

## Process

1. Confirm the current workspace is the Flutter app repo or sub-repo that owns
   the code being debugged, not the MCP tooling repo.
2. Locate app bootstrap, `ProviderScope`, router construction, Talker setup,
   and centralized network logging or client wrappers.
3. Add path or git dependencies to the app:

```yaml
dependencies:
  flutter_agent_runtime:
    path: <path-to-tooling-repo>/packages/flutter_agent_runtime
  flutter_agent_runtime_adapters:
    path: <path-to-tooling-repo>/packages/flutter_agent_runtime_adapters
```

Adjust paths for the app location. If work uses git dependencies or an internal
package registry, use that form instead. Do not add
`flutter_agent_mcp_server` as an app runtime dependency; keep it in agent/tooling
configuration.

4. Initialize before `runApp` from debug/development bootstrap code:

```dart
AgentRuntime.init();
AgentRuntime.installErrorHooks();
```

5. Append `const AgentProviderObserver()` to existing Riverpod observers.
6. Append `AgentGoRouterObserver()` to GoRouter observers and forward redirects
   or route errors from existing router callbacks where available.
7. Add `AgentTalkerObserver` as the Talker observer, or create a composite
   observer if the app already has one.
8. Add `AgentNetworkObserver.recordRequest(...)` in the existing HTTP/Dio/network
   logging layer. Record metadata only. Do not capture request or response
   bodies.
9. Run the smallest relevant validation:

```bash
flutter pub get
flutter analyze
flutter test
```

Use package-specific commands if the app is inside a larger monorepo.

## Constraints

- Do not remove existing Talker, Riverpod, or GoRouter observers.
- Do not change business logic while adding runtime forwarding.
- Keep instrumentation debug-safe and local-development focused.
- If an existing observer already normalizes names or values, forward those normalized shapes into `AgentRuntime.instance.recordProviderEvent`, `recordRouteEvent`, or `log` rather than duplicating normalization logic.

## Validation With MCP

After code changes, ask the developer to run the app in debug mode and provide
the VM Service URL. Confirm the current app repo's MCP client can see
`flutter-agent-runtime`, then use:

```text
connect_to_app
flutter_diagnostics_bundle
riverpod_state
go_router_state
app_logs
network_requests
widget_rebuilds
```

Confirm that the diagnostics bundle contains non-empty capability data for the integration points that were wired.
