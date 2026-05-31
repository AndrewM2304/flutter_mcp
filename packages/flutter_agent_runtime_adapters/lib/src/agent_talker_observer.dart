import 'package:flutter_agent_runtime/flutter_agent_runtime.dart';
import 'package:talker/talker.dart';

class AgentTalkerObserver extends TalkerObserver {
  const AgentTalkerObserver({this.source = 'talker'});

  final String source;

  @override
  void onLog(TalkerData log) {
    _record(log);
  }

  @override
  void onError(TalkerError err) {
    _record(err);
    final error = err.error;
    final stackTrace = err.stackTrace;
    if (error != null && stackTrace != null) {
      AgentRuntime.instance.recordError(error, stackTrace, source: source);
    }
  }

  @override
  void onException(TalkerException err) {
    _record(err);
    final exception = err.exception;
    final stackTrace = err.stackTrace;
    if (exception != null && stackTrace != null) {
      AgentRuntime.instance.recordError(exception, stackTrace, source: source);
    }
  }

  void _record(TalkerData data) {
    AgentRuntime.instance.recordLog(
      data.message ?? data.displayMessage,
      level: data.logLevel?.name ?? data.runtimeType.toString(),
      source: source,
      error: data.error ?? data.exception,
      stackTrace: data.stackTrace,
      fields: {
        'title': data.title,
        'key': data.key,
        'talkerType': data.runtimeType.toString(),
        'time': data.time.toIso8601String(),
        'displayTitle': data.displayTitleWithTime(),
      },
    );
  }
}
