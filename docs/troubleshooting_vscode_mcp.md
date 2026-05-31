# Troubleshooting VS Code MCP Loading

If VS Code hangs on `Starting MCP servers flutter-agent-runtime... Skip?` on every
chat message, work through these checks in order.

## What Skip Actually Means

Pressing **Skip** lets chat continue without the `flutter-agent-runtime` server.
After Skip, Copilot often falls back to Dart SDK MCP tools such as Dart Tooling
Daemon, Widget Inspector, and Flutter Driver. Those tools do **not** expose
Riverpod provider values, GoRouter agent events, Talker logs, or agent runtime
network metadata.

If you Skip and then ask for app state, the agent may read source code and report
wrong values such as counter `0` when the live value is `3`. Fix MCP startup
instead of continuing after Skip.

## 1. Start MCP Manually Once Per Session

This repo sets `"chat.mcp.autostart": "never"` in `.vscode/settings.json` so VS
Code does not retry a failing autostart on every chat message.

Before using the Flutter Runtime Debugger agent:

1. Run **MCP: List Servers**
2. Start `flutter-agent-runtime`
3. Confirm the server shows as running before sending chat messages

## 2. Confirm The Server Starts Outside VS Code

From the tooling repo root:

```bash
./tool/validate.sh
dart tool/mcp_stdio_smoke.dart
```

You should see `[initialize] ok` and `[tools/list] ok`.

## 3. Fix `dart` Not Found In VS Code

VS Code launched from the Dock on macOS often has a smaller `PATH` than your
terminal. If MCP startup hangs or the log never appears, ensure `.vscode/mcp.json`
includes a `PATH` that contains your Flutter/Dart SDK:

```json
{
  "servers": {
    "flutter-agent-runtime": {
      "type": "stdio",
      "command": "dart",
      "args": [
        "${workspaceFolder}/packages/flutter_agent_mcp_server/bin/flutter_agent_mcp_server.dart"
      ],
      "env": {
        "PATH": "${env:HOME}/Development/flutter/bin:/opt/homebrew/bin:/usr/local/bin:${env:PATH}"
      }
    }
  }
}
```

Adjust the Flutter SDK path for your machine.

## 4. Use The Launcher Script From The App Repo

When debugging a Flutter app in a different repo, do not copy a relative `packages/...` path into the app repo. VS Code starts MCP servers with the app workspace as the working directory, so relative paths to the tooling repo will fail.

Copy [app.mcp.json](templates/app.mcp.json) into the app repo as `.vscode/mcp.json`. The first start prompts for the absolute tooling repo path and then runs `tool/start_flutter_agent_mcp_server.sh`, which resolves the server script from its own location.

Do not use `dart run flutter_agent_mcp_server`. Package build output on stdout breaks stdio MCP.

## 5. Require `"type": "stdio"`

VS Code expects stdio servers to declare the connection type explicitly:

```json
{
  "servers": {
    "flutter-agent-runtime": {
      "type": "stdio",
      "command": "/bin/bash",
      "args": ["/absolute/path/to/tooling/tool/start_flutter_agent_mcp_server.sh"]
    }
  }
}
```

## 6. Reload MCP After Config Changes

Run **MCP: List Servers**, restart `flutter-agent-runtime`, or reload the VS Code window after editing `.vscode/mcp.json`.

If tools changed, also run **MCP: Reset Cached Tools**.

## 7. Check Server Activity

While reproducing the issue, open:

```text
.dart_tool/flutter_agent_mcp_server.log
```

in the workspace VS Code uses as the MCP process working directory. Normal startup lines look like:

```text
[flutter_agent_mcp_server] server started; waiting for MCP client messages
[flutter_agent_mcp_server] received initialize request
[flutter_agent_mcp_server] received notifications/initialized notification
[flutter_agent_mcp_server] received tools/list request
```

If the log never appears, the MCP client did not launch the process successfully. Check that `dart` is on PATH for the VS Code process and that the launcher script path is correct.

If the log stops after `server started` with no `initialize` line, the client
may be sending newline-delimited JSON while an older server build only parsed
Content-Length frames. Update to the latest tooling repo and restart the server.

## 8. Expose Agents And Skills From External Repos

Custom agents and skills are discovered from the current workspace by default. If the agent definitions live in a separate repo, add [work.vscode.settings.json](templates/work.vscode.settings.json) values to the app repo `.vscode/settings.json`, or copy the agent and skills folders into:

```text
~/.copilot/agents
~/.copilot/skills
```

Do not put MCP tool wildcards such as `flutter-agent-runtime/*` in agent frontmatter. VS Code can validate tool names before the MCP server finishes loading, which causes the chat to stall until you press Skip.

## 9. Network Access For Live Debugging

After the MCP server loads, `connect_to_app` talks to the local Flutter VM Service on `127.0.0.1`. If you enable MCP sandboxing for this server, allow localhost network access or leave sandboxing disabled for local VM Service debugging.
