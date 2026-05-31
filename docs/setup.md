# Setup

## App Dependencies

Add the runtime and adapters packages to the Flutter app under development:

```yaml
dependencies:
  flutter_agent_runtime:
    path: ../mcp/packages/flutter_agent_runtime
  flutter_agent_runtime_adapters:
    path: ../mcp/packages/flutter_agent_runtime_adapters
```

Use the relative path that matches the app repository layout.

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
