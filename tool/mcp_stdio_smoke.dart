import 'dart:collection';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  if (options.showHelp) {
    stdout.writeln(_usage);
    return;
  }

  final process = await Process.start(
    'dart',
    ['packages/flutter_agent_mcp_server/bin/flutter_agent_mcp_server.dart'],
    workingDirectory: options.repoRoot,
  );

  final stderrSub = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => stderr.writeln(line));
  final reader = _McpReader(process.stdout);

  try {
    final initialize = await _call(
      process,
      reader,
      id: 1,
      method: 'initialize',
      params: <String, Object?>{},
    );
    _printResult('initialize', initialize);

    final tools = await _call(
      process,
      reader,
      id: 2,
      method: 'tools/list',
      params: <String, Object?>{},
    );
    _printResult('tools/list', tools);

    final prompts = await _call(
      process,
      reader,
      id: 3,
      method: 'prompts/list',
      params: <String, Object?>{},
    );
    _printResult('prompts/list', prompts);

    if (options.vmServiceUri != null) {
      final connect = await _call(
        process,
        reader,
        id: 4,
        method: 'tools/call',
        params: {
          'name': 'connect_to_app',
          'arguments': {
            'uri': options.vmServiceUri,
            if (options.workspaceRoot != null)
              'workspace_root': options.workspaceRoot,
          },
        },
      );
      _printResult('connect_to_app', connect);

      final diagnostics = await _call(
        process,
        reader,
        id: 5,
        method: 'tools/call',
        params: {
          'name': 'flutter_diagnostics_bundle',
          'arguments': <String, Object?>{},
        },
      );
      _printResult('flutter_diagnostics_bundle', diagnostics);
    }
  } finally {
    process.stdin.close();
    await reader.close();
    await process.exitCode.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        process.kill();
        return process.exitCode;
      },
    );
    await stderrSub.cancel();
  }
}

Future<Map<String, Object?>> _call(
  Process process,
  _McpReader reader, {
  required int id,
  required String method,
  required Map<String, Object?> params,
}) async {
  final body = jsonEncode({
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': params,
  });
  process.stdin.add(utf8.encode('$body\n'));
  await process.stdin.flush();

  final response = await reader.next.timeout(
    const Duration(seconds: 35),
    onTimeout: () => throw TimeoutException('No MCP response for $method'),
  );
  if (response['error'] != null) {
    throw StateError('$method failed: ${jsonEncode(response['error'])}');
  }
  return response;
}

void _printResult(String label, Map<String, Object?> response) {
  final result = response['result'];
  stdout.writeln('[$label] ok');
  if (result is Map && result['tools'] is List) {
    final names = (result['tools'] as List)
        .whereType<Map>()
        .map((tool) => tool['name'])
        .whereType<String>()
        .join(', ');
    stdout.writeln('  tools: $names');
  }
  if (result is Map && result['prompts'] is List) {
    final names = (result['prompts'] as List)
        .whereType<Map>()
        .map((prompt) => prompt['name'])
        .whereType<String>()
        .join(', ');
    stdout.writeln('  prompts: $names');
  }
}

class _McpReader {
  _McpReader(Stream<List<int>> input) {
    _sub = input.listen(_add);
  }

  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final Queue<Map<String, Object?>> _messages = Queue<Map<String, Object?>>();
  final Queue<Completer<Map<String, Object?>>> _waiters =
      Queue<Completer<Map<String, Object?>>>();
  late final StreamSubscription<List<int>> _sub;

  Future<Map<String, Object?>> get next {
    if (_messages.isNotEmpty) {
      return Future.value(_messages.removeFirst());
    }
    final completer = Completer<Map<String, Object?>>();
    _waiters.add(completer);
    return completer.future;
  }

  void _add(List<int> chunk) {
    _buffer.add(chunk);
    _drain();
  }

  void _drain() {
    List<int> bytes = _buffer.takeBytes();
    while (bytes.isNotEmpty) {
      if (_startsWithContentLengthHeader(bytes)) {
        final remaining = _consumeContentLengthFrame(bytes);
        if (remaining == null) {
          _buffer.add(bytes);
          return;
        }
        bytes = remaining;
        continue;
      }

      final newlineIndex = _indexOfNewline(bytes);
      if (newlineIndex < 0) {
        _buffer.add(bytes);
        return;
      }

      var lineEnd = newlineIndex;
      if (newlineIndex > 0 && bytes[newlineIndex - 1] == 13) {
        lineEnd = newlineIndex - 1;
      }

      final line = utf8.decode(bytes.sublist(0, lineEnd)).trim();
      bytes = bytes.sublist(newlineIndex + 1);
      if (line.isEmpty) {
        continue;
      }

      final decoded = jsonDecode(line);
      if (decoded is Map) {
        _addMessage(Map<String, Object?>.from(decoded));
      }
    }
  }

  List<int>? _consumeContentLengthFrame(List<int> bytes) {
    final headerEnd = _headerEnd(bytes);
    if (headerEnd < 0) {
      return null;
    }
    final header = utf8.decode(bytes.sublist(0, headerEnd));
    final length = _contentLength(header);
    if (length == null) {
      _addError(FormatException('Missing Content-Length header'));
      return const [];
    }
    final bodyStart = headerEnd + 4;
    final bodyEnd = bodyStart + length;
    if (bytes.length < bodyEnd) {
      return null;
    }
    final decoded = jsonDecode(utf8.decode(bytes.sublist(bodyStart, bodyEnd)));
    if (decoded is Map) {
      _addMessage(Map<String, Object?>.from(decoded));
    }
    return bytes.sublist(bodyEnd);
  }

  bool _startsWithContentLengthHeader(List<int> bytes) {
    final prefixLength = bytes.length < 16 ? bytes.length : 16;
    final prefix = utf8.decode(bytes.sublist(0, prefixLength)).toLowerCase();
    return prefix.startsWith('content-length:');
  }

  int _indexOfNewline(List<int> bytes) {
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 10) {
        return i;
      }
    }
    return -1;
  }

  int _headerEnd(List<int> bytes) {
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  int? _contentLength(String header) {
    for (final line in header.split('\r\n')) {
      final separator = line.indexOf(':');
      if (separator < 0) continue;
      if (line.substring(0, separator).trim().toLowerCase() ==
          'content-length') {
        return int.tryParse(line.substring(separator + 1).trim());
      }
    }
    return null;
  }

  Future<void> close() async {
    await _sub.cancel();
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().completeError(StateError('MCP reader closed.'));
    }
  }

  void _addMessage(Map<String, Object?> message) {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(message);
    } else {
      _messages.add(message);
    }
  }

  void _addError(Object error) {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().completeError(error);
    }
  }
}

class _Options {
  const _Options({
    required this.repoRoot,
    this.vmServiceUri,
    this.workspaceRoot,
    this.showHelp = false,
  });

  final String repoRoot;
  final String? vmServiceUri;
  final String? workspaceRoot;
  final bool showHelp;

  static _Options parse(List<String> args) {
    var repoRoot = Directory.current.path;
    String? vmServiceUri;
    String? workspaceRoot;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '-h':
        case '--help':
          return _Options(repoRoot: repoRoot, showHelp: true);
        case '--repo-root':
          repoRoot = _requiredValue(args, ++i, arg);
        case '--vm-service-uri':
          vmServiceUri = _requiredValue(args, ++i, arg);
        case '--workspace-root':
          workspaceRoot = _requiredValue(args, ++i, arg);
        default:
          throw ArgumentError('Unknown argument: $arg\n\n$_usage');
      }
    }

    return _Options(
      repoRoot: repoRoot,
      vmServiceUri: vmServiceUri,
      workspaceRoot: workspaceRoot,
    );
  }

  static String _requiredValue(List<String> args, int index, String flag) {
    if (index >= args.length) {
      throw ArgumentError('$flag requires a value.');
    }
    return args[index];
  }
}

const _usage = '''
Usage:
  dart tool/mcp_stdio_smoke.dart
  dart tool/mcp_stdio_smoke.dart --vm-service-uri <uri> --workspace-root <app-root>

Without --vm-service-uri, this verifies MCP initialize and tools/list only.
With --vm-service-uri, it also connects to a running debug Flutter app and calls
flutter_diagnostics_bundle.
''';
