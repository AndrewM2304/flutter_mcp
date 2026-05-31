# Runtime Data Shapes

All runtime events include:

```json
{
  "id": 42,
  "schemaVersion": "agent-runtime.event.v1",
  "type": "provider",
  "timestamp": "2026-05-31T12:00:00.000000",
  "severity": "info",
  "source": "riverpod",
  "data": {}
}
```

## Provider Event

```json
{
  "action": "add | update | dispose | error",
  "source": "riverpod",
  "provider": "counterProvider",
  "providerType": "StateProvider<int>",
  "previousValue": 1,
  "nextValue": 2,
  "error": {
    "type": "StateError",
    "message": "Bad state",
    "stackTrace": "..."
  }
}
```

`flutter_snapshot.current.providers` stores the latest known provider value by provider name.

## Route Event

```json
{
  "action": "push | pop | replace | redirect | error",
  "source": "go_router",
  "location": "/home",
  "previousLocation": "/login",
  "stack": ["/login", "/home"],
  "matchedLocation": "/home",
  "fullPath": "/home",
  "pathParameters": {},
  "queryParameters": {}
}
```

`flutter_snapshot.current.route` stores the latest known route state.

## Log Event

```json
{
  "message": "Counter incremented",
  "level": "info",
  "tags": ["ui"],
  "fields": {
    "count": 2
  }
}
```

## Network Event

```json
{
  "method": "GET",
  "url": "https://api.example.test/items",
  "host": "api.example.test",
  "statusCode": 200,
  "durationMs": 42.0,
  "requestHeaders": {
    "authorization": "<redacted>"
  },
  "responseHeaders": {}
}
```

Request and response bodies are intentionally absent in v1.

Headers matching the configured redaction list are replaced with
`"<redacted>"`. Runtime maps such as provider values, log fields, route
arguments, and network attributes also redact configured sensitive field names
such as tokens, passwords, cookies, and API keys. Long serialized strings are
truncated to keep responses bounded.

## Rebuild Event

```json
{
  "widget": "HomeScreen",
  "count": 14,
  "location": "/absolute/path/lib/home_screen.dart:42",
  "id": "123",
  "durationSeconds": "3",
  "source": "mcp_widget_rebuilds"
}
```

Rebuild data comes from Flutter inspector service extensions and is sampled when `widget_rebuilds` is called.

## Diagnostics Bundle

`flutter_diagnostics_bundle` returns:

```json
{
  "schemaVersion": "agent-runtime.diagnostics.v1",
  "status": {},
  "currentRoute": {},
  "providerCount": 12,
  "recentProviderChanges": [],
  "latestErrors": [],
  "failedNetworkRequests": [],
  "topRebuildHotspots": [],
  "recentLogs": []
}
```
