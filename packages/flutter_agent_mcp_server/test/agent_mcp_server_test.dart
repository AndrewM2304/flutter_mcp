import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_agent_mcp_server/src/agent_mcp_server.dart';
import 'package:test/test.dart';

void main() {
  test('handles NDJSON initialize, tools/list, and not_connected tool call', () async {
    final input = StreamController<List<int>>();
    final output = StreamController<List<int>>.broadcast();
    final server = AgentMcpServer(input.stream, _ListSink(output));
    unawaited(server.run());

    final responses = <Map<String, Object?>>[];
    final outputSub = output.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty) return;
      responses.add(Map<String, Object?>.from(jsonDecode(line) as Map));
    });

    Future<Map<String, Object?>> roundTrip(Map<String, Object?> request) async {
      final before = responses.length;
      input.add(utf8.encode('${jsonEncode(request)}\n'));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (responses.length <= before) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('No MCP response for ${request['method']}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return responses.last;
    }

    final initialize = await roundTrip({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 'test', 'version': '1.0'},
      },
    });
    expect(initialize['result'], isA<Map>());
    final initResult = Map<String, Object?>.from(initialize['result'] as Map);
    expect(initResult['serverInfo'], isA<Map>());

    input.add(utf8.encode(
      '${jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized', 'params': {}})}\n',
    ));

    final toolsList = await roundTrip({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/list',
      'params': {},
    });
    final tools = (toolsList['result'] as Map)['tools'] as List;
    final toolNames = tools
        .whereType<Map>()
        .map((tool) => tool['name'])
        .whereType<String>()
        .toList();
    expect(toolNames, contains('connect_and_diagnose'));
    expect(toolNames, contains('flutter_diagnostics_bundle'));

    final diagnostics = await roundTrip({
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': {
        'name': 'flutter_diagnostics_bundle',
        'arguments': {},
      },
    });
    final result = Map<String, Object?>.from(diagnostics['result'] as Map);
    final content = (result['content'] as List).first as Map;
    final payload =
        jsonDecode(content['text'] as String) as Map<String, Object?>;
    expect(payload['ok'], isFalse);
    expect(payload['reason'], 'not_connected');

    final status = await roundTrip({
      'jsonrpc': '2.0',
      'id': 4,
      'method': 'tools/call',
      'params': {
        'name': 'connection_status',
        'arguments': {},
      },
    });
    final statusResult = Map<String, Object?>.from(status['result'] as Map);
    final statusContent = (statusResult['content'] as List).first as Map;
    final statusPayload = jsonDecode(statusContent['text'] as String)
        as Map<String, Object?>;
    expect(statusPayload['connected'], isFalse);

    await input.close();
    await outputSub.cancel();
  });
}

class _ListSink implements IOSink {
  _ListSink(this._output);

  final StreamController<List<int>> _output;

  @override
  void add(List<int> data) => _output.add(data);

  @override
  Future<void> flush() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
