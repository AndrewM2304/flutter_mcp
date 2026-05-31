class AgentRuntimeConfig {
  const AgentRuntimeConfig({
    this.eventBufferSize = 500,
    this.providerBufferSize = 300,
    this.routeBufferSize = 200,
    this.logBufferSize = 500,
    this.networkBufferSize = 300,
    this.rebuildBufferSize = 300,
    this.errorBufferSize = 100,
    this.redactedHeaderNames = const {
      'authorization',
      'cookie',
      'set-cookie',
      'x-api-key',
      'x-auth-token',
      'proxy-authorization',
    },
    this.redactedFieldNames = const {
      'access_token',
      'api_key',
      'apikey',
      'auth_token',
      'authorization',
      'cookie',
      'id_token',
      'password',
      'refresh_token',
      'secret',
      'session',
      'token',
    },
    this.maxSerializedStringLength = 500,
  });

  final int eventBufferSize;
  final int providerBufferSize;
  final int routeBufferSize;
  final int logBufferSize;
  final int networkBufferSize;
  final int rebuildBufferSize;
  final int errorBufferSize;
  final Set<String> redactedHeaderNames;
  final Set<String> redactedFieldNames;
  final int maxSerializedStringLength;

  AgentRuntimeConfig copyWith({
    int? eventBufferSize,
    int? providerBufferSize,
    int? routeBufferSize,
    int? logBufferSize,
    int? networkBufferSize,
    int? rebuildBufferSize,
    int? errorBufferSize,
    Set<String>? redactedHeaderNames,
    Set<String>? redactedFieldNames,
    int? maxSerializedStringLength,
  }) {
    return AgentRuntimeConfig(
      eventBufferSize: eventBufferSize ?? this.eventBufferSize,
      providerBufferSize: providerBufferSize ?? this.providerBufferSize,
      routeBufferSize: routeBufferSize ?? this.routeBufferSize,
      logBufferSize: logBufferSize ?? this.logBufferSize,
      networkBufferSize: networkBufferSize ?? this.networkBufferSize,
      rebuildBufferSize: rebuildBufferSize ?? this.rebuildBufferSize,
      errorBufferSize: errorBufferSize ?? this.errorBufferSize,
      redactedHeaderNames: redactedHeaderNames ?? this.redactedHeaderNames,
      redactedFieldNames: redactedFieldNames ?? this.redactedFieldNames,
      maxSerializedStringLength:
          maxSerializedStringLength ?? this.maxSerializedStringLength,
    );
  }

  Map<String, Object?> toJson() => {
        'eventBufferSize': eventBufferSize,
        'providerBufferSize': providerBufferSize,
        'routeBufferSize': routeBufferSize,
        'logBufferSize': logBufferSize,
        'networkBufferSize': networkBufferSize,
        'rebuildBufferSize': rebuildBufferSize,
        'errorBufferSize': errorBufferSize,
        'redactedHeaderNames': redactedHeaderNames.toList()..sort(),
        'redactedFieldNames': redactedFieldNames.toList()..sort(),
        'maxSerializedStringLength': maxSerializedStringLength,
      };
}
