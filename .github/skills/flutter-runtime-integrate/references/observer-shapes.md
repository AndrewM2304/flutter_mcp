# Observer Shape Guidance

## Riverpod

Append the agent observer:

```dart
ProviderScope(
  observers: [
    existingObserver,
    const AgentProviderObserver(),
  ],
  child: child,
)
```

If an existing observer owns naming or value summarization, forward the same shape:

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

## GoRouter

Append the agent route observer:

```dart
final agentRouteObserver = AgentGoRouterObserver();

GoRouter(
  observers: [
    existingRouteObserver,
    agentRouteObserver,
  ],
)
```

Forward redirects from the existing redirect callback:

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

## Talker

If Talker already has an observer, use a composite observer that forwards to both the existing observer and `AgentTalkerObserver`. Do not replace existing logging behavior.

## Network

Forward metadata only:

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

Headers are redacted by runtime defaults. Bodies are intentionally not captured in v1.
