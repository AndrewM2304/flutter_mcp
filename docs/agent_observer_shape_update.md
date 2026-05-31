# One-Time Agent Instructions: Observer Shape Update

Use this guide when updating a Flutter app that already has Talker, Riverpod, and GoRouter observers.

## Goal

Keep all existing observers working and add agent runtime forwarding beside them. Do not replace existing observer behavior.

## Steps

1. Add local dependencies:

```yaml
dependencies:
  flutter_agent_runtime:
    path: ../mcp/packages/flutter_agent_runtime
  flutter_agent_runtime_adapters:
    path: ../mcp/packages/flutter_agent_runtime_adapters
```

2. Import the packages near the app bootstrap/router/logger setup:

```dart
import 'package:flutter_agent_runtime/flutter_agent_runtime.dart';
import 'package:flutter_agent_runtime_adapters/flutter_agent_runtime_adapters.dart';
```

3. Initialize runtime before `runApp`:

```dart
AgentRuntime.init();
AgentRuntime.installErrorHooks();
```

If the app already wraps startup in `runZonedGuarded`, keep that wrapper and call `AgentRuntime.instance.recordError(error, stackTrace, source: 'zone')` from the existing error callback.

4. Riverpod:

Find the existing `ProviderScope(observers: [...])` and append `const AgentProviderObserver()`.

```dart
ProviderScope(
  observers: [
    existingObserver,
    const AgentProviderObserver(),
  ],
  child: child,
)
```

If the app has a custom Riverpod observer that already normalizes provider names or values, update that observer to call:

```dart
AgentRuntime.instance.recordProviderEvent(
  action: 'update',
  provider: providerName,
  providerType: providerType,
  previousValue: previousValue,
  nextValue: nextValue,
  source: 'existing_riverpod_observer',
  attributes: {
    'scope': scopeName,
  },
);
```

5. GoRouter:

Append `AgentGoRouterObserver` to the router observers list.

```dart
final agentRouteObserver = AgentGoRouterObserver();

GoRouter(
  observers: [
    existingTalkerRouteObserver,
    agentRouteObserver,
  ],
)
```

If the router uses redirects, add forwarding inside the existing redirect function:

```dart
final target = existingRedirectLogic(context, state);
if (target != null) {
  agentRouteObserver.recordGoRouterRedirect(
    state: state,
    targetLocation: target,
    reason: 'existing_redirect',
  );
}
return target;
```

If the app has route error handling, call `recordGoRouterError`.

6. Talker:

If Talker has no observer, use:

```dart
Talker(observer: const AgentTalkerObserver());
```

If Talker already has an observer, create or update a composite observer that forwards each callback to the existing observer and to `AgentTalkerObserver`. Do not drop the existing observer.

7. Network:

Where the app already centralizes HTTP/Dio/client logging, add metadata-only forwarding:

```dart
AgentNetworkObserver.recordRequest(
  method: method,
  url: uri,
  statusCode: statusCode,
  duration: duration,
  requestHeaders: headers,
  responseHeaders: responseHeaders,
  requestSizeBytes: requestSize,
  responseSizeBytes: responseSize,
  error: error,
  stackTrace: stackTrace,
);
```

Do not pass request or response bodies.

8. Validate with MCP:

Call tools in this order:

```text
connect_to_app
get_app_info
flutter_diagnostics_bundle
riverpod_state
go_router_state
app_logs
network_requests
widget_rebuilds
```

The expected result is that `flutter_diagnostics_bundle` includes current route, provider count, recent logs, latest errors, failed network requests, and rebuild hotspots after `widget_rebuilds` has been sampled once.

## Do Not

- Remove existing Talker, Riverpod, or GoRouter observers.
- Capture network bodies by default.
- Add runtime forwarding to release-only code paths.
- Change provider business logic while adding observers.
