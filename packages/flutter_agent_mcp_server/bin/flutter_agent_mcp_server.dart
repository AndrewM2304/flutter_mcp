import 'dart:io';

import 'package:flutter_agent_mcp_server/src/agent_mcp_server.dart';

Future<void> main() async {
  if (stdin.hasTerminal) {
    stderr.writeln(
      'flutter_agent_mcp_server is an MCP stdio server. It is meant to be '
      'started by an MCP client such as VS Code, not used interactively.',
    );
    stderr.writeln(
      'If this process appears idle, it is waiting for MCP JSON-RPC messages '
      'on stdin. See docs/using_with_agents.md for the workflow.',
    );
  }

  final server = AgentMcpServer(stdin, stdout);
  await server.run();
}
