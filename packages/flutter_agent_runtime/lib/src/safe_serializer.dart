typedef AgentValueSerializer = Object? Function(Object? value);

class SafeSerializer {
  SafeSerializer({Iterable<AgentValueSerializer> serializers = const []})
      : _serializers = List<AgentValueSerializer>.of(serializers);

  final List<AgentValueSerializer> _serializers;

  void addSerializer(AgentValueSerializer serializer) {
    _serializers.add(serializer);
  }

  Object? serialize(Object? value, {int depth = 4}) {
    for (final serializer in _serializers) {
      final serialized = serializer(value);
      if (serialized != null) {
        return serialize(serialized, depth: depth - 1);
      }
    }

    if (value == null || value is String || value is num || value is bool) {
      return value;
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
        result[entry.key.toString()] = serialize(entry.value, depth: depth - 1);
      }
      return result;
    }
    return _summary(value);
  }

  Map<String, Object?> _summary(Object? value) => {
        'type': value.runtimeType.toString(),
        'summary': value.toString(),
      };
}
