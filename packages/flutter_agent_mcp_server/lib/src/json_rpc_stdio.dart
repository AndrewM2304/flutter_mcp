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
    final body = utf8.encode(jsonEncode(message));
    output.add(utf8.encode('Content-Length: ${body.length}\r\n\r\n'));
    output.add(body);
  }

  void _drain(BytesBuilder builder) {
    var bytes = builder.takeBytes();
    while (true) {
      final headerEnd = _indexOfHeaderEnd(bytes);
      if (headerEnd < 0) {
        builder.add(bytes);
        return;
      }

      final header = utf8.decode(bytes.sublist(0, headerEnd));
      final length = _contentLength(header);
      if (length == null) {
        _messages.addError(FormatException('Missing Content-Length header'));
        return;
      }

      final bodyStart = headerEnd + 4;
      final bodyEnd = bodyStart + length;
      if (bytes.length < bodyEnd) {
        builder.add(bytes);
        return;
      }

      final body = utf8.decode(bytes.sublist(bodyStart, bodyEnd));
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        _messages.add(Map<String, Object?>.from(decoded));
      }
      bytes = bytes.sublist(bodyEnd);
      if (bytes.isEmpty) return;
    }
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
