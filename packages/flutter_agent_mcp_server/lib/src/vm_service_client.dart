import 'dart:async';
import 'dart:convert';
import 'dart:io';

class VmServiceClient {
  VmServiceClient._(this._socket);

  final WebSocket _socket;
  int _nextId = 1;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  final StreamController<Map<String, Object?>> _extensionEvents =
      StreamController<Map<String, Object?>>.broadcast();

  String? isolateId;

  Stream<Map<String, Object?>> get extensionEvents => _extensionEvents.stream;

  static Future<VmServiceClient> connect(String uri) async {
    final socket = await WebSocket.connect(_normalizeToWsUri(uri));
    final client = VmServiceClient._(socket);
    client._listen();
    await client._selectMainIsolate();
    return client;
  }

  Future<void> close() async {
    await _extensionEvents.close();
    await _socket.close();
  }

  Future<Map<String, Object?>> getVm() => call('getVM');

  Future<Map<String, Object?>> getIsolate([String? id]) async {
    final target = id ?? isolateId;
    if (target == null) {
      throw StateError('No isolate selected.');
    }
    return call('getIsolate', {'isolateId': target});
  }

  Future<Map<String, Object?>> streamListen(String streamId) {
    return call('streamListen', {'streamId': streamId});
  }

  Future<Map<String, Object?>> callServiceExtension(
    String serviceMethod, {
    Map<String, Object?> args = const {},
  }) async {
    final target = isolateId;
    if (target == null) {
      throw StateError('No isolate selected.');
    }
    return call(serviceMethod, {
      'isolateId': target,
      ...args.map((key, value) => MapEntry(key, value.toString())),
    });
  }

  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('VM Service call timed out: $method');
      },
    );
  }

  Future<void> _selectMainIsolate() async {
    final vm = await getVm();
    final isolates = (vm['isolates'] as List?) ?? const [];
    if (isolates.isEmpty) return;
    final first = Map<String, Object?>.from(isolates.first as Map);
    isolateId = first['id'] as String?;
  }

  void _listen() {
    _socket.listen(
      (message) {
        final decoded = jsonDecode(message as String);
        if (decoded is! Map) return;
        final map = Map<String, Object?>.from(decoded);
        final id = map['id'];
        if (id is int && _pending.containsKey(id)) {
          final completer = _pending.remove(id)!;
          if (map.containsKey('error')) {
            completer.completeError(VmServiceException(map['error']));
          } else {
            completer.complete(Map<String, Object?>.from(map['result'] as Map));
          }
          return;
        }
        if (map['method'] == 'streamNotify') {
          final params = map['params'];
          if (params is Map && params['streamId'] == 'Extension') {
            final event = params['event'];
            if (event is Map) {
              _extensionEvents.add(Map<String, Object?>.from(event));
            }
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        for (final completer in _pending.values) {
          completer.completeError(error, stackTrace);
        }
        _pending.clear();
      },
      onDone: () {
        for (final completer in _pending.values) {
          completer.completeError(StateError('VM Service socket closed.'));
        }
        _pending.clear();
      },
    );
  }

  static String _normalizeToWsUri(String uri) {
    var value = uri.trim();
    if (!value.startsWith('ws')) {
      value = value
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');
    }
    if (!value.endsWith('/ws')) {
      value = value.replaceAll(RegExp(r'/?$'), '/ws');
    }
    return value;
  }
}

class VmServiceException implements Exception {
  VmServiceException(this.error);

  final Object? error;

  @override
  String toString() => 'VM Service error: $error';
}
