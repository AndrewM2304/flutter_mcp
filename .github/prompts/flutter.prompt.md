---
description: Start Flutter runtime debugging with the Flutter Runtime Debugger agent.
agent: Flutter Runtime Debugger
argument-hint: "[VM Service or DevTools URL] [workspace root] [optional goal]"
---

Use the `flutter-agent-runtime` MCP server.

Connect to my running Flutter app, then show the session recording workflow.

Inputs I provide after `/flutter` may include:

- Flutter VM Service or DevTools URL
- app workspace root
- optional debugging goal or symptom

If either the URL or workspace root is missing, ask only for the missing value.
Once both are available, call `connect_and_diagnose` with `summary: true`.

After connecting, offer:

1. Start recording a session
2. Stop and review everything
3. Stop and review errors/logs
4. Stop and review network calls
5. Stop and review rebuilds
6. Stop and review provider changes
7. Stop and review navigation
8. Stop and create a bug report

Accept either a number or free text for the next step.
