import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class JsonRpcStdio {
  JsonRpcStdio(this.input, this.output);

  final Stream<List<int>> input;
  final IOSink output;
  final StreamController<Map<String, Object?>> _messages =
      StreamController<Map<String, Object?>>();

  Stream<Map<String, Object?>> get messages => _messages.stream;

  Future<void> start() async {
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in input) {
      buffer.add(chunk);
      _drain(buffer);
    }
    await _messages.close();
  }

  void send(Map<String, Object?> message) {
    // MCP stdio uses newline-delimited JSON (VS Code, Claude, Copilot).
    output.add(utf8.encode('${jsonEncode(message)}\n'));
    unawaited(output.flush().catchError((_) {}));
  }

  void _drain(BytesBuilder builder) {
    List<int> bytes = builder.takeBytes();
    while (bytes.isNotEmpty) {
      if (_startsWithContentLengthHeader(bytes)) {
        final remaining = _consumeContentLengthFrame(bytes);
        if (remaining == null) {
          builder.add(bytes);
          return;
        }
        bytes = remaining;
        continue;
      }

      final newlineIndex = _indexOfNewline(bytes);
      if (newlineIndex < 0) {
        builder.add(bytes);
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

      _addDecodedLine(line);
    }
  }

  List<int>? _consumeContentLengthFrame(List<int> bytes) {
    final headerEnd = _indexOfHeaderEnd(bytes);
    if (headerEnd < 0) {
      return null;
    }

    final header = utf8.decode(bytes.sublist(0, headerEnd));
    final length = _contentLength(header);
    if (length == null) {
      _messages.addError(FormatException('Missing Content-Length header'));
      return const [];
    }

    final bodyStart = headerEnd + 4;
    final bodyEnd = bodyStart + length;
    if (bytes.length < bodyEnd) {
      return null;
    }

    final body = utf8.decode(bytes.sublist(bodyStart, bodyEnd));
    _addDecodedLine(body);
    return bytes.sublist(bodyEnd);
  }

  void _addDecodedLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map) {
        _messages.add(Map<String, Object?>.from(decoded));
      }
    } on FormatException catch (error) {
      _messages.addError(error);
    }
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

  int _indexOfHeaderEnd(List<int> bytes) {
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
      final name = line.substring(0, separator).trim().toLowerCase();
      if (name == 'content-length') {
        return int.tryParse(line.substring(separator + 1).trim());
      }
    }
    return null;
  }
}
