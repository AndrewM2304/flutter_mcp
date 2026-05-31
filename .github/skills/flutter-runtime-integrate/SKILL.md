---
name: flutter-runtime-integrate
description: Add or update in-house flutter_agent_runtime integration in a Flutter app, including runtime initialization, Riverpod ProviderObserver forwarding, GoRouter observer and redirect forwarding, Talker observer forwarding, and metadata-only network request recording. Use when asked to wire the runtime into an app or update existing observer data shapes.
argument-hint: "[Flutter app path]"
---

# Flutter Runtime Integration

This skill updates app code so agents can inspect runtime state through the local MCP server. Follow [observer shape guidance](./references/observer-shapes.md) and keep all existing observers working.

## Process

1. Locate app bootstrap, `ProviderScope`, router construction, Talker setup, and centralized network logging or client wrappers.
2. Add path dependencies to the app:

```yaml
dependencies:
  flutter_agent_runtime:
    path: ../mcp/packages/flutter_agent_runtime
  flutter_agent_runtime_adapters:
    path: ../mcp/packages/flutter_agent_runtime_adapters
```

Adjust relative paths for the app location.

3. Initialize before `runApp`:

```dart
AgentRuntime.init();
AgentRuntime.installErrorHooks();
```

4. Append `const AgentProviderObserver()` to existing Riverpod observers.
5. Append `AgentGoRouterObserver()` to GoRouter observers and forward redirects or route errors from existing router callbacks where available.
6. Add `AgentTalkerObserver` as the Talker observer, or create a composite observer if the app already has one.
7. Add `AgentNetworkObserver.recordRequest(...)` in the existing HTTP/Dio/network logging layer. Record metadata only. Do not capture request or response bodies.
8. Run the smallest relevant validation:

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

After code changes, ask the developer to run the app in debug mode and provide the VM Service URL. Then use:

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
