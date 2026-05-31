import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_agent_mcp_server/src/agent_mcp_server.dart';
import 'package:test/test.dart';

void main() {
  test('handles NDJSON initialize, tools/list, and not_connected tool call',
      () async {
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
      '${jsonEncode({
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
            'params': {}
          })}\n',
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
    expect(toolNames, contains('start_flow_recording'));
    expect(toolNames, contains('stop_flow_recording'));
    expect(toolNames, contains('flow_recording_status'));
    expect(toolNames, contains('diagnose_current_screen'));
    expect(toolNames, contains('investigate_latest_error'));
    expect(toolNames, contains('trace_navigation_issue'));
    expect(toolNames, contains('check_runtime_integration'));

    final promptsList = await roundTrip({
      'jsonrpc': '2.0',
      'id': 'prompts-list',
      'method': 'prompts/list',
      'params': {},
    });
    final prompts = (promptsList['result'] as Map)['prompts'] as List;
    final promptNames = prompts
        .whereType<Map>()
        .map((prompt) => prompt['name'])
        .whereType<String>()
        .toList();
    expect(promptNames, ['startFlutterRuntimeDebugger']);

    final prompt = await roundTrip({
      'jsonrpc': '2.0',
      'id': 'prompt-get',
      'method': 'prompts/get',
      'params': {
        'name': 'startFlutterRuntimeDebugger',
        'arguments': {
          'uri': 'http://127.0.0.1:1234/abc=/',
          'workspaceRoot': '/tmp/flutter_app',
          'goal': 'login fails after OTP',
        },
      },
    });
    final promptResult = Map<String, Object?>.from(prompt['result'] as Map);
    final messages = promptResult['messages'] as List;
    final firstMessage = Map<String, Object?>.from(messages.first as Map);
    final promptContent =
        Map<String, Object?>.from(firstMessage['content'] as Map);
    expect(promptContent['text'], contains('http://127.0.0.1:1234/abc=/'));
    expect(promptContent['text'], contains('/tmp/flutter_app'));
    expect(promptContent['text'], contains('login fails after OTP'));
    expect(promptContent['text'], contains('Start recording a session'));

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
    final statusPayload =
        jsonDecode(statusContent['text'] as String) as Map<String, Object?>;
    expect(statusPayload['connected'], isFalse);

    for (final toolName in [
      'start_flow_recording',
      'diagnose_current_screen',
      'investigate_latest_error',
      'trace_navigation_issue',
      'check_runtime_integration',
    ]) {
      final response = await roundTrip({
        'jsonrpc': '2.0',
        'id': 'not-connected-$toolName',
        'method': 'tools/call',
        'params': {
          'name': toolName,
          'arguments': {},
        },
      });
      final responseResult =
          Map<String, Object?>.from(response['result'] as Map);
      final responseContent = (responseResult['content'] as List).first as Map;
      final responsePayload =
          jsonDecode(responseContent['text'] as String) as Map<String, Object?>;
      expect(responsePayload['ok'], isFalse, reason: toolName);
      expect(responsePayload['reason'], 'not_connected', reason: toolName);
    }

    final flowStatus = await roundTrip({
      'jsonrpc': '2.0',
      'id': 5,
      'method': 'tools/call',
      'params': {
        'name': 'flow_recording_status',
        'arguments': {},
      },
    });
    final flowStatusResult =
        Map<String, Object?>.from(flowStatus['result'] as Map);
    final flowStatusContent =
        (flowStatusResult['content'] as List).first as Map;
    final flowStatusPayload =
        jsonDecode(flowStatusContent['text'] as String) as Map<String, Object?>;
    expect(flowStatusPayload['ok'], isTrue);
    expect(flowStatusPayload['active'], isFalse);

    final stopFlow = await roundTrip({
      'jsonrpc': '2.0',
      'id': 6,
      'method': 'tools/call',
      'params': {
        'name': 'stop_flow_recording',
        'arguments': {},
      },
    });
    final stopFlowResult = Map<String, Object?>.from(stopFlow['result'] as Map);
    final stopFlowContent = (stopFlowResult['content'] as List).first as Map;
    final stopFlowPayload =
        jsonDecode(stopFlowContent['text'] as String) as Map<String, Object?>;
    expect(stopFlowPayload['ok'], isFalse);
    expect(stopFlowPayload['reason'], 'no_active_flow');

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
