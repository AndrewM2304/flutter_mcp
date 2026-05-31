# Using The MCP Server With Agents

## Key Point

`flutter_agent_mcp_server` is not a web server and does not open a port.

It is an MCP stdio server. That means an MCP client starts it as a child process and talks to it over stdin/stdout. If you run this command by hand:

```bash
dart <path-to-tooling-repo>/packages/flutter_agent_mcp_server/bin/flutter_agent_mcp_server.dart
```

it is normal for it to appear idle. It is waiting for an MCP client.

## Normal Workflow

### 1. Start The Flutter App

In terminal 1:

```bash
cd <flutter-app-repo>
flutter run -d macos
```

Wait for Flutter to print a line like:

```text
The Dart VM Service is listening on http://127.0.0.1:XXXXX/abc123=/
```

Copy that full URL.

### 2. Let The App Repo Agent Start The MCP Server

In the Flutter app repo or app sub-repo, configure the agent client to start the
server from the external tooling repo:

```text
.vscode/mcp.json
```

Copy [templates/app.mcp.json](../templates/app.mcp.json) into the app repo, or
use this shape directly:

```json
{
  "inputs": [
    {
      "type": "promptString",
      "id": "flutter-agent-tooling-path",
      "description": "Absolute path to the flutter agent MCP tooling repo on this machine"
    }
  ],
  "servers": {
    "flutter-agent-runtime": {
      "type": "stdio",
      "command": "/bin/bash",
      "args": [
        "${input:flutter-agent-tooling-path}/tool/start_flutter_agent_mcp_server.sh"
      ]
    }
  }
}
```

Reload VS Code or the agent client so it discovers this MCP config. The current
chat can be in the app repo; the MCP server does not need to live under that
repo.

Do not configure VS Code MCP with `dart run flutter_agent_mcp_server`. `dart run` can print package build messages to stdout before the MCP response, and stdio MCP requires stdout to contain only protocol messages.

Do not point the app repo at a relative `packages/flutter_agent_mcp_server/...`
path. VS Code starts MCP servers with the app workspace as the working
directory, so that path will not exist outside the tooling repo.

If VS Code hangs while loading the MCP server, see
[troubleshooting_vscode_mcp.md](../troubleshooting_vscode_mcp.md).

### 3. Ask The Agent To Connect

In the agent chat, say something like:

```text
Use the flutter-agent-runtime MCP server.
Connect to my running Flutter app with VM Service URI:
http://127.0.0.1:XXXXX/abc123=/
workspace_root:
<absolute-path-to-flutter-app-repo>
Then run flutter_diagnostics_bundle.
```

The agent should call:

```json
{
  "name": "connect_to_app",
  "arguments": {
    "uri": "http://127.0.0.1:XXXXX/abc123=/",
    "workspace_root": "<absolute-path-to-flutter-app-repo>"
  }
}
```

Then it can call:

```text
flutter_diagnostics_bundle
riverpod_state
go_router_state
app_logs
network_requests
widget_rebuilds
```

The MCP server also exposes one scoped starter prompt so Flutter runtime
debugging does not pollute the global workspace prompt-file list. In VS Code,
type `/mcp.` and choose:

```text
/mcp.flutter-agent-runtime.startFlutterRuntimeDebugger
```

There is also one short workspace prompt for discoverability:

```text
/flutter
```

The `/flutter` prompt is tied to the **Flutter Runtime Debugger** agent and is
intended to be the easy-to-find entry point when the MCP prompt is not surfaced
by the current VS Code build.

After the first diagnostic response, the Flutter Runtime Debugger agent is
oriented around recording a session first, then reviewing that recorded window
through a specific lens. The handoff buttons are configured with `send: true`,
so selecting **Record Session** submits immediately and the agent should call
`start_flow_recording`; it should not merely prefill a message for the user to
send. After the user stops the session, review buttons focus the same recording
on everything, errors/logs, network calls, rebuilds, provider changes,
navigation, or a bug report.

VS Code prompts for the prompt arguments when provided by the MCP server: VM
Service or DevTools URL, workspace root, and an optional goal. The starter prompt
connects first, runs a diagnostic pass, then offers the session recording and
review workflow.

MCP prompts are scoped to the MCP server. They are not the same as workspace
prompt files, so they avoid mixing Flutter runtime workflows with unrelated
workspace or extension prompts.

For richer initial UI with buttons, selects, and forms directly in chat, VS Code
requires either a VS Code chat extension or MCP Apps. The stdio MCP server now
uses MCP prompts because they are supported by VS Code without adding a separate
extension package.

The underlying Flutter runtime skills are marked `user-invocable: false` so they
remain available to agents without appearing as competing slash commands.

## Manual Smoke Test

You usually do not need this. It only proves the stdio protocol works.

```bash
dart tool/mcp_stdio_smoke.dart
```

You should see:

```text
[initialize] ok
[tools/list] ok
```

For a live app smoke test, start the Flutter app in debug mode, copy the VM
Service URI, then run:

```bash
dart tool/mcp_stdio_smoke.dart \
  --vm-service-uri "http://127.0.0.1:XXXXX/abc123=/" \
  --workspace-root "<absolute-path-to-flutter-app-repo>"
```

## What Not To Do

- Do not type commands into the terminal where `dart <path-to-tooling-repo>/packages/flutter_agent_mcp_server/bin/flutter_agent_mcp_server.dart` is waiting.
- Do not expect a localhost URL from the MCP server.
- Do not paste the Flutter VM Service URL into the MCP server terminal. Give it to the agent, and the agent calls `connect_to_app`.

## What You Should See In VS Code Output

Open **Output** and choose **MCP Gateway**. Some VS Code builds only show gateway-level messages there and do not expose child server stderr as a separate output channel.

For reliable visibility, the server also writes a workspace log file:

```text
.dart_tool/flutter_agent_mcp_server.log
```

Open that file while you use the agent. Normal output looks like:

```text
[flutter_agent_mcp_server] server started; waiting for MCP client messages
[flutter_agent_mcp_server] received initialize request
[flutter_agent_mcp_server] tool started: connect_to_app
[flutter_agent_mcp_server] connecting to Flutter VM Service: http://127.0.0.1:XXXXX/...
[flutter_agent_mcp_server] connected to Flutter app; workspace=/path/to/app
[flutter_agent_mcp_server] tool finished: connect_to_app ok=true elapsed=...
```

For rebuild tracking:

```text
[flutter_agent_mcp_server] tool started: widget_rebuilds
[flutter_agent_mcp_server] rebuild sampling requested: 3s
[flutter_agent_mcp_server] loading widget location map
[flutter_agent_mcp_server] rebuild tracking enabled; interact with the app now
[flutter_agent_mcp_server] rebuild tracking disabled
[flutter_agent_mcp_server] rebuild sample complete: rawEvents=... widgets=...
```

The detailed app state is not printed automatically into Output. Agents see it by calling MCP tools such as `flutter_diagnostics_bundle`, `riverpod_state`, `go_router_state`, `app_logs`, `network_requests`, and `widget_rebuilds`.

Agents can also call `mcp_activity_log` to return recent server activity lines.
