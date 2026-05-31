# Agent Instructions

This repository contains an in-house Flutter runtime instrumentation package and a local MCP stdio server for VS Code agents.

## Rules

- Keep the MCP server stdout protocol-only. Human-readable diagnostics must go to stderr or `.dart_tool/flutter_agent_mcp_server.log`.
- Prefer `dart packages/flutter_agent_mcp_server/bin/flutter_agent_mcp_server.dart` in MCP configuration over `dart run flutter_agent_mcp_server`.
- Keep app integration additive. Do not remove existing Riverpod, GoRouter, or Talker observers when adding agent runtime forwarding.
- Keep network capture metadata-only unless a future explicit feature changes the privacy model.
- Use bounded buffers and safe serialization for runtime data.

## Useful Validation

```bash
dart analyze
dart test packages/flutter_agent_mcp_server
flutter analyze packages/flutter_agent_runtime
flutter test packages/flutter_agent_runtime
flutter analyze packages/flutter_agent_runtime_adapters
flutter analyze examples/runtime_sample_app
flutter test examples/runtime_sample_app
```

## VS Code Customizations

- Custom agent: `.github/agents/flutter-runtime-debugger.agent.md`
- Debug skill: `.github/skills/flutter-runtime-debug/SKILL.md`
- Integration skill: `.github/skills/flutter-runtime-integrate/SKILL.md`
