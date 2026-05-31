# Diagnostics Shape Reference

Use this reference when reading MCP tool output. Prefer live fields over event
history or source code.

## First Call After Connect

Prefer `connect_and_diagnose` or this sequence:

```text
connect_to_app
flutter_diagnostics_bundle
```

Use `flutter_diagnostics_bundle` with `"summary": true` when you only need current
state and a short recent history.

## `flutter_diagnostics_bundle`

Key paths in the `data` object:

| Path | Meaning |
|------|---------|
| `currentProviders.<name>.value` | Latest live provider value |
| `currentProviders.<name>.lastAction` | Last lifecycle action (`add`, `update`, `dispose`) |
| `currentRoute.location` | Current GoRouter location |
| `currentRoute.stack` | Route stack when available |
| `providerCount` | Number of tracked providers |
| `recentProviderChanges[]` | Recent provider events (may be older than `currentProviders`) |
| `latestErrors[]` | Recent runtime errors |
| `failedNetworkRequests[]` | Failed or 4xx/5xx network metadata |
| `recentLogs[]` | Structured Talker/runtime logs |
| `topRebuildHotspots[]` | Known rebuild hotspots from runtime buffer |
| `status.capabilities` | Which instrumentation is active |

Example provider read:

```json
{
  "currentProviders": {
    "counterProvider": {
      "provider": "counterProvider",
      "value": 2,
      "lastAction": "update"
    }
  }
}
```

Report `currentProviders.<name>.value` as the live value. Use
`recentProviderChanges` only for history and timestamps.

## `riverpod_state`

| Path | Meaning |
|------|---------|
| `current` | Map of latest provider states (same shape as snapshot providers) |
| `events.events[]` | Filtered provider events |

## `go_router_state`

| Path | Meaning |
|------|---------|
| `current` | Latest route state |
| `events.events[]` | Recent navigation events |

## `connect_and_diagnose`

Returns:

| Path | Meaning |
|------|---------|
| `connection` | Result of `connect_to_app` |
| `diagnostics` | Diagnostics bundle payload |
| `connection.app.capabilities` | Whether agent runtime extensions are available |

## Not Connected

When a tool returns:

```json
{
  "ok": false,
  "reason": "not_connected"
}
```

Call `connect_to_app`, `connect_and_diagnose`, or `reconnect_last` before retrying.

## Instrumentation Missing

When runtime extensions are unavailable:

```json
{
  "ok": false,
  "reason": "instrumentation_missing"
}
```

Use the `flutter-runtime-integrate` skill. Do not substitute Dart SDK MCP tools.
