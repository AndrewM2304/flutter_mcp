import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_agent_mcp_server/src/json_rpc_stdio.dart';
import 'package:flutter_agent_mcp_server/src/vm_service_client.dart';
import 'package:test/test.dart';

void main() {
  test('parses content-length framed json rpc messages', () async {
    final input = StreamController<List<int>>();
    final output = StringBuffer();
    final sink = _StringSink(output);
    final rpc = JsonRpcStdio(input.stream, sink);

    unawaited(rpc.start());
    final body = jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'});
    input.add(
      utf8.encode('Content-Length: ${utf8.encode(body).length}\r\n\r\n$body'),
    );
    await input.close();

    final message = await rpc.messages.first;
    expect(message['method'], 'ping');
  });

  test('normalizes VM Service HTTP URLs to WebSocket URLs', () {
    expect(
      VmServiceClient.normalizeToWsUri('http://127.0.0.1:1234/abc=/'),
      'ws://127.0.0.1:1234/abc=/ws',
    );
  });

  test('normalizes DevTools URLs using the embedded VM Service URI', () {
    expect(
      VmServiceClient.normalizeToWsUri(
        'http://127.0.0.1:9100/abc=/devtools/?'
        'uri=ws://127.0.0.1:1234/abc=/ws',
      ),
      'ws://127.0.0.1:1234/abc=/ws',
    );
  });
}

class _StringSink implements IOSink {
  _StringSink(this.buffer);

  final StringBuffer buffer;

  @override
  void add(List<int> data) => buffer.write(utf8.decode(data));

  @override
  void write(Object? object) => buffer.write(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
