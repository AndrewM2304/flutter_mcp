# Using The MCP Server With Agents

## Key Point

`flutter_agent_mcp_server` is not a web server and does not open a port.

It is an MCP stdio server. That means an MCP client starts it as a child process and talks to it over stdin/stdout. If you run this command by hand:

```bash
dart packages/flutter_agent_mcp_server/bin/flutter_agent_mcp_server.dart
```

it is normal for it to appear idle. It is waiting for an MCP client.

## Normal Workflow

### 1. Start The Flutter App

In terminal 1:

```bash
cd /Users/andrewmiller/Development/mcp/examples/runtime_sample_app
flutter run -d macos
```

Wait for Flutter to print a line like:

```text
The Dart VM Service is listening on http://127.0.0.1:XXXXX/abc123=/
```

Copy that full URL.

### 2. Let VS Code Start The MCP Server

The repo contains:

```text
.vscode/mcp.json
```

with this server:

```json
{
  "servers": {
    "flutter-agent-runtime": {
      "command": "dart",
      "args": ["packages/flutter_agent_mcp_server/bin/flutter_agent_mcp_server.dart"]
    }
  }
}
```

Reload VS Code so it discovers this MCP config.

Do not configure VS Code MCP with `dart run flutter_agent_mcp_server`. `dart run` can print package build messages to stdout before the MCP response, and stdio MCP requires stdout to contain only protocol messages.

### 3. Ask The Agent To Connect

In the agent chat, say something like:

```text
Use the flutter-agent-runtime MCP server.
Connect to my running Flutter app with VM Service URI:
http://127.0.0.1:XXXXX/abc123=/
workspace_root:
/Users/andrewmiller/Development/mcp/examples/runtime_sample_app
Then run flutter_diagnostics_bundle.
```

The agent should call:

```json
{
  "name": "connect_to_app",
  "arguments": {
    "uri": "http://127.0.0.1:XXXXX/abc123=/",
    "workspace_root": "/Users/andrewmiller/Development/mcp/examples/runtime_sample_app"
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

## Manual Smoke Test

You usually do not need this. It only proves the stdio protocol works.

```bash
printf 'Content-Length: 58\r\n\r\n{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  | dart packages/flutter_agent_mcp_server/bin/flutter_agent_mcp_server.dart
```

You should see a response starting with:

```text
Content-Length:
```

If the content length is wrong, the server will wait for more bytes and appear stuck.

## What Not To Do

- Do not type commands into the terminal where `dart packages/flutter_agent_mcp_server/bin/flutter_agent_mcp_server.dart` is waiting.
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
