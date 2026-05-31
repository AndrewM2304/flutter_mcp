typedef AgentValueSerializer = Object? Function(Object? value);

class SafeSerializer {
  SafeSerializer({
    Iterable<AgentValueSerializer> serializers = const [],
    Iterable<String> redactedKeys = const [],
    this.maxStringLength = 500,
  })  : _serializers = List<AgentValueSerializer>.of(serializers),
        _redactedKeys = redactedKeys.map(_normalizeKey).toSet();

  final List<AgentValueSerializer> _serializers;
  final Set<String> _redactedKeys;
  final int maxStringLength;

  void addSerializer(AgentValueSerializer serializer) {
    _serializers.add(serializer);
  }

  SafeSerializer copyWith({
    Iterable<String>? redactedKeys,
    int? maxStringLength,
  }) {
    return SafeSerializer(
      serializers: _serializers,
      redactedKeys: redactedKeys ?? _redactedKeys,
      maxStringLength: maxStringLength ?? this.maxStringLength,
    );
  }

  Object? serialize(Object? value, {int depth = 4}) {
    for (final serializer in _serializers) {
      final serialized = serializer(value);
      if (serialized != null) {
        return serialize(serialized, depth: depth - 1);
      }
    }

    if (value == null || value is num || value is bool) {
      return value;
    }
    if (value is String) {
      return _truncate(value);
    }
    if (depth <= 0) {
      return _summary(value);
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Uri) {
      return value.toString();
    }
    if (value is Iterable) {
      return value
          .take(50)
          .map((item) => serialize(item, depth: depth - 1))
          .toList();
    }
    if (value is Map) {
      final result = <String, Object?>{};
      var count = 0;
      for (final entry in value.entries) {
        if (count++ >= 50) break;
        final key = entry.key.toString();
        result[key] = _isRedactedKey(key)
            ? '<redacted>'
            : serialize(entry.value, depth: depth - 1);
      }
      return result;
    }
    return _summary(value);
  }

  Map<String, Object?> _summary(Object? value) => {
        'type': value.runtimeType.toString(),
        'summary': _truncate(value.toString()),
      };

  bool _isRedactedKey(String key) => _redactedKeys.contains(_normalizeKey(key));

  String _truncate(String value) {
    if (maxStringLength <= 0 || value.length <= maxStringLength) {
      return value;
    }
    return '${value.substring(0, maxStringLength)}...<truncated>';
  }

  static String _normalizeKey(String key) {
    return key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
