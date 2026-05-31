import 'agent_runtime.dart';

class AgentNetworkObserver {
  const AgentNetworkObserver();

  static void recordRequest({
    required String method,
    required Uri url,
    int? statusCode,
    Duration? duration,
    DateTime? startedAt,
    DateTime? endedAt,
    Map<String, Object?> requestHeaders = const {},
    Map<String, Object?> responseHeaders = const {},
    int? requestSizeBytes,
    int? responseSizeBytes,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> attributes = const {},
  }) {
    AgentRuntime.instance.recordNetworkRequest(
      method: method,
      url: url,
      statusCode: statusCode,
      duration: duration,
      startedAt: startedAt,
      endedAt: endedAt,
      requestHeaders: requestHeaders,
      responseHeaders: responseHeaders,
      requestSizeBytes: requestSizeBytes,
      responseSizeBytes: responseSizeBytes,
      error: error,
      stackTrace: stackTrace,
      attributes: attributes,
    );
  }
}
