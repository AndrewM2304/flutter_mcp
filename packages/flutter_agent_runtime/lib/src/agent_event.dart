class AgentEvent {
  AgentEvent({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.data,
    this.severity = 'info',
    this.source,
    this.schemaVersion = 'agent-runtime.event.v1',
  });

  final int id;
  final String schemaVersion;
  final String type;
  final DateTime timestamp;
  final String severity;
  final String? source;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
        'id': id,
        'schemaVersion': schemaVersion,
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'severity': severity,
        if (source != null) 'source': source,
        'data': data,
      };
}
