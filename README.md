# Flutter Agent Runtime MCP

In-house local development tooling that exposes a running Flutter app to agents through MCP.

This repository intentionally does not depend on `flutter_agent_lens`. That project was used only as reference material for VM Service and Flutter inspector techniques.

## Packages

- `packages/flutter_agent_runtime`: core debug-only Flutter runtime instrumentation.
- `packages/flutter_agent_runtime_adapters`: optional Riverpod, GoRouter, and Talker adapters.
- `packages/flutter_agent_mcp_server`: Dart MCP stdio server with direct VM Service JSON-RPC.
- `examples/runtime_sample_app`: sample app for manual validation.

## Local Usage

1. Add the runtime and adapters packages to a Flutter app with local path dependencies.
2. Call `AgentRuntime.init()` before `runApp`.
3. Add optional Riverpod, GoRouter, and Talker adapters.
4. Start the app in debug mode.
5. Run the MCP server and call `connect_to_app` with the Flutter VM Service URI.

The runtime is debug-only by default and no-ops in release builds.

```yaml
dependencies:
  flutter_agent_runtime:
    path: ../mcp/packages/flutter_agent_runtime
  flutter_agent_runtime_adapters:
    path: ../mcp/packages/flutter_agent_runtime_adapters
```

```dart
void main() {
  AgentRuntime.init();
  AgentRuntime.installErrorHooks();

  runApp(ProviderScope(
    observers: [
      existingRiverpodObserver,
      AgentProviderObserver(),
    ],
    child: const App(),
  ));
}
```

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

```dart
final talker = Talker(
  observer: AgentTalkerObserver(),
);
```

The MCP server exposes `flutter_diagnostics_bundle` as the preferred first call for agents. It returns current route, provider activity, latest errors, failed network requests, top rebuild hotspots, and recent logs in one response.

## Docs

- [Setup](docs/setup.md)
- [Using with agents](docs/using_with_agents.md)
- [Runtime data shapes](docs/data_shapes.md)
- [One-time observer shape update instructions](docs/agent_observer_shape_update.md)
