import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'agent_event.dart';
import 'agent_runtime_config.dart';
import 'ring_buffer.dart';
import 'safe_serializer.dart';

class AgentRuntime {
  AgentRuntime._();

  static const schemaVersion = 'agent-runtime.snapshot.v1';
  static final AgentRuntime instance = AgentRuntime._();

  bool _initialized = false;
  bool _errorHooksInstalled = false;
  int _nextEventId = 1;
  AgentRuntimeConfig _config = const AgentRuntimeConfig();
  SafeSerializer _serializer = SafeSerializer();
  FlutterExceptionHandler? _previousFlutterErrorHandler;
  ui.ErrorCallback? _previousPlatformErrorHandler;

  late RingBuffer<AgentEvent> _events;
  late RingBuffer<AgentEvent> _providers;
  late RingBuffer<AgentEvent> _routes;
  late RingBuffer<AgentEvent> _logs;
  late RingBuffer<AgentEvent> _network;
  late RingBuffer<AgentEvent> _rebuilds;
  late RingBuffer<AgentEvent> _errors;
  final Map<String, Map<String, Object?>> _providerState =
      <String, Map<String, Object?>>{};
  final Map<String, Object?> _routeState = <String, Object?>{};

  static bool get isEnabled => !kReleaseMode && instance._initialized;

  static void init({
    AgentRuntimeConfig config = const AgentRuntimeConfig(),
    Iterable<AgentValueSerializer> serializers = const [],
  }) {
    if (kReleaseMode) return;
    instance._init(config: config, serializers: serializers);
  }

  void _init({
    required AgentRuntimeConfig config,
    required Iterable<AgentValueSerializer> serializers,
  }) {
    if (_initialized) return;
    _config = config;
    _serializer = SafeSerializer(
      serializers: serializers,
      redactedKeys: _config.redactedFieldNames,
      maxStringLength: _config.maxSerializedStringLength,
    );
    _events = RingBuffer<AgentEvent>(_config.eventBufferSize);
    _providers = RingBuffer<AgentEvent>(_config.providerBufferSize);
    _routes = RingBuffer<AgentEvent>(_config.routeBufferSize);
    _logs = RingBuffer<AgentEvent>(_config.logBufferSize);
    _network = RingBuffer<AgentEvent>(_config.networkBufferSize);
    _rebuilds = RingBuffer<AgentEvent>(_config.rebuildBufferSize);
    _errors = RingBuffer<AgentEvent>(_config.errorBufferSize);
    _initialized = true;

    developer.registerExtension('ext.agentRuntime.status', _statusExtension);
    developer.registerExtension(
      'ext.agentRuntime.snapshot',
      _snapshotExtension,
    );
    developer.registerExtension('ext.agentRuntime.events', _eventsExtension);
    developer.registerExtension(
      'ext.agentRuntime.configure',
      _configureExtension,
    );
    developer.registerExtension(
      'ext.agentRuntime.diagnostics',
      _diagnosticsExtension,
    );
    developer.registerExtension(
      'ext.agentRuntime.recordRebuildSummary',
      _recordRebuildSummaryExtension,
    );
  }

  static void installErrorHooks({bool forwardToExistingHandlers = true}) {
    if (kReleaseMode) return;
    instance._installErrorHooks(
      forwardToExistingHandlers: forwardToExistingHandlers,
    );
  }

  static R? runGuarded<R>(
    R Function() body, {
    AgentRuntimeConfig config = const AgentRuntimeConfig(),
    Iterable<AgentValueSerializer> serializers = const [],
    bool forwardToExistingHandlers = true,
  }) {
    init(config: config, serializers: serializers);
    installErrorHooks(forwardToExistingHandlers: forwardToExistingHandlers);
    return runZonedGuarded<R>(
      body,
      (error, stackTrace) {
        instance.recordError(error, stackTrace, source: 'zone');
      },
    );
  }

  void _installErrorHooks({required bool forwardToExistingHandlers}) {
    if (_errorHooksInstalled) return;
    _previousFlutterErrorHandler = FlutterError.onError;
    _previousPlatformErrorHandler = ui.PlatformDispatcher.instance.onError;

    FlutterError.onError = (details) {
      recordError(
        details.exception,
        details.stack ?? StackTrace.current,
        source: 'FlutterError',
      );
      if (forwardToExistingHandlers && _previousFlutterErrorHandler != null) {
        _previousFlutterErrorHandler!(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    ui.PlatformDispatcher.instance.onError = (error, stackTrace) {
      recordError(error, stackTrace, source: 'PlatformDispatcher');
      if (forwardToExistingHandlers && _previousPlatformErrorHandler != null) {
        return _previousPlatformErrorHandler!(error, stackTrace);
      }
      return false;
    };

    _errorHooksInstalled = true;
  }

  void addValueSerializer(AgentValueSerializer serializer) {
    if (kReleaseMode) return;
    _serializer.addSerializer(serializer);
  }

  void recordProviderEvent({
    required String action,
    required String provider,
    String? providerType,
    String source = 'riverpod',
    Object? previousValue,
    Object? nextValue,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> attributes = const {},
  }) {
    final serializedPrevious = _serializer.serialize(previousValue);
    final serializedNext = _serializer.serialize(nextValue);
    if (_initialized) {
      if (action == 'dispose') {
        _providerState.remove(provider);
      } else {
        _providerState[provider] = {
          'provider': provider,
          if (providerType != null) 'providerType': providerType,
          'lastAction': action,
          'source': source,
          'updatedAt': DateTime.now().toIso8601String(),
          'value': serializedNext,
          ..._serializeMap(attributes),
          if (error != null) 'error': _errorJson(error, stackTrace),
        };
      }
    }
    _record(
      type: 'provider',
      source: source,
      severity: error == null ? 'info' : 'error',
      data: {
        'action': action,
        'provider': provider,
        'source': source,
        if (providerType != null) 'providerType': providerType,
        'previousValue': serializedPrevious,
        'nextValue': serializedNext,
        ..._serializeMap(attributes),
        if (error != null) 'error': _errorJson(error, stackTrace),
      },
      specificBuffer: _providers,
    );
  }

  void recordRouteEvent({
    required String action,
    String source = 'go_router',
    String? location,
    String? previousLocation,
    List<String> stack = const [],
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> attributes = const {},
  }) {
    if (_initialized) {
      _routeState
        ..['lastAction'] = action
        ..['source'] = source
        ..['updatedAt'] = DateTime.now().toIso8601String()
        ..['stack'] = stack
        ..addAll(_serializeMap(attributes));
      if (location != null) {
        _routeState['location'] = location;
      }
      if (previousLocation != null) {
        _routeState['previousLocation'] = previousLocation;
      }
      if (error != null) {
        _routeState['error'] = _errorJson(error, stackTrace);
      }
    }
    _record(
      type: 'route',
      source: source,
      severity: error == null ? 'info' : 'error',
      data: {
        'action': action,
        'source': source,
        if (location != null) 'location': location,
        if (previousLocation != null) 'previousLocation': previousLocation,
        'stack': stack,
        ..._serializeMap(attributes),
        if (error != null) 'error': _errorJson(error, stackTrace),
      },
      specificBuffer: _routes,
    );
  }

  static void log(
    String message, {
    String level = 'info',
    String? source,
    List<String> tags = const [],
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    instance.recordLog(
      message,
      level: level,
      source: source,
      tags: tags,
      error: error,
      stackTrace: stackTrace,
      fields: fields,
    );
  }

  void recordLog(
    String message, {
    String level = 'info',
    String? source,
    List<String> tags = const [],
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    _record(
      type: 'log',
      source: source,
      severity: level,
      data: {
        'message': message,
        'level': level,
        'tags': tags,
        'fields': _serializeMap(fields),
        if (error != null) 'error': _errorJson(error, stackTrace),
      },
      specificBuffer: _logs,
    );
  }

  void recordNetworkRequest({
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
    _record(
      type: 'network',
      source: 'app',
      severity: error == null ? 'info' : 'error',
      data: {
        'method': method,
        'url': url.toString(),
        'host': url.host,
        if (statusCode != null) 'statusCode': statusCode,
        if (duration != null) 'durationMs': duration.inMicroseconds / 1000.0,
        if (startedAt != null) 'startedAt': startedAt.toIso8601String(),
        if (endedAt != null) 'endedAt': endedAt.toIso8601String(),
        'requestHeaders': _redactHeaders(requestHeaders),
        'responseHeaders': _redactHeaders(responseHeaders),
        if (requestSizeBytes != null) 'requestSizeBytes': requestSizeBytes,
        if (responseSizeBytes != null) 'responseSizeBytes': responseSizeBytes,
        ..._serializeMap(attributes),
        if (error != null) 'error': _errorJson(error, stackTrace),
      },
      specificBuffer: _network,
    );
  }

  void recordRebuildSummary({
    required String widget,
    required int count,
    String? location,
    String? id,
    Map<String, Object?> attributes = const {},
  }) {
    _record(
      type: 'rebuild',
      source: 'flutter_inspector',
      data: {
        'widget': widget,
        'count': count,
        if (location != null) 'location': location,
        if (id != null) 'id': id,
        ..._serializeMap(attributes),
      },
      specificBuffer: _rebuilds,
    );
  }

  void recordError(Object error, StackTrace stackTrace, {String? source}) {
    _record(
      type: 'error',
      source: source,
      severity: 'error',
      data: _errorJson(error, stackTrace),
      specificBuffer: _errors,
    );
  }

  AgentEvent _record({
    required String type,
    required Map<String, Object?> data,
    String severity = 'info',
    String? source,
    RingBuffer<AgentEvent>? specificBuffer,
  }) {
    if (kReleaseMode || !_initialized) {
      return AgentEvent(
        id: -1,
        type: type,
        timestamp: DateTime.now(),
        data: data,
      );
    }
    final event = AgentEvent(
      id: _nextEventId++,
      type: type,
      timestamp: DateTime.now(),
      severity: severity,
      source: source,
      data: data,
    );
    _events.add(event);
    specificBuffer?.add(event);
    if (severity == 'error' && specificBuffer != _errors) {
      _errors.add(event);
    }
    return event;
  }

  Future<developer.ServiceExtensionResponse> _statusExtension(
    String method,
    Map<String, String> parameters,
  ) async {
    return developer.ServiceExtensionResponse.result(
      _jsonString(_statusJson()),
    );
  }

  Future<developer.ServiceExtensionResponse> _snapshotExtension(
    String method,
    Map<String, String> parameters,
  ) async {
    return developer.ServiceExtensionResponse.result(
      _jsonString(_snapshotJson()),
    );
  }

  Future<developer.ServiceExtensionResponse> _eventsExtension(
    String method,
    Map<String, String> parameters,
  ) async {
    final type = parameters['type'];
    final since = int.tryParse(parameters['since'] ?? '');
    final limit = int.tryParse(parameters['limit'] ?? '') ?? 100;
    final events = _events
        .where(
          (event) =>
              (type == null || event.type == type) &&
              (since == null || event.id > since),
        )
        .take(limit.clamp(1, 500))
        .map((event) => event.toJson())
        .toList();
    return developer.ServiceExtensionResponse.result(
      _jsonString({
        'events': events,
        'nextCursor': events.isEmpty ? since : events.last['id'],
      }),
    );
  }

  Future<developer.ServiceExtensionResponse> _configureExtension(
    String method,
    Map<String, String> parameters,
  ) async {
    final redacted = parameters['redactedHeaders'];
    if (redacted != null && redacted.trim().isNotEmpty) {
      _config = _config.copyWith(
        redactedHeaderNames: redacted
            .split(',')
            .map((header) => header.trim().toLowerCase())
            .where((header) => header.isNotEmpty)
            .toSet(),
      );
    }
    final redactedFields = parameters['redactedFields'];
    if (redactedFields != null && redactedFields.trim().isNotEmpty) {
      _config = _config.copyWith(
        redactedFieldNames: redactedFields
            .split(',')
            .map((field) => field.trim().toLowerCase())
            .where((field) => field.isNotEmpty)
            .toSet(),
      );
    }
    final maxStringLength = int.tryParse(
      parameters['maxSerializedStringLength'] ?? '',
    );
    if (maxStringLength != null) {
      _config = _config.copyWith(
        maxSerializedStringLength: maxStringLength.clamp(0, 10000).toInt(),
      );
    }
    _serializer = _serializer.copyWith(
      redactedKeys: _config.redactedFieldNames,
      maxStringLength: _config.maxSerializedStringLength,
    );
    return developer.ServiceExtensionResponse.result(
      _jsonString({'ok': true, 'config': _config.toJson()}),
    );
  }

  Future<developer.ServiceExtensionResponse> _diagnosticsExtension(
    String method,
    Map<String, String> parameters,
  ) async {
    return developer.ServiceExtensionResponse.result(
      _jsonString(_diagnosticsJson()),
    );
  }

  Future<developer.ServiceExtensionResponse> _recordRebuildSummaryExtension(
    String method,
    Map<String, String> parameters,
  ) async {
    recordRebuildSummary(
      widget: parameters['widget'] ?? 'unknown',
      count: int.tryParse(parameters['count'] ?? '') ?? 0,
      location: parameters['location'],
      id: parameters['id'],
      attributes: {
        if (parameters['durationSeconds'] != null)
          'durationSeconds': parameters['durationSeconds'],
        if (parameters['source'] != null) 'source': parameters['source'],
      },
    );
    return developer.ServiceExtensionResponse.result(
      _jsonString({'ok': true}),
    );
  }

  Map<String, Object?> _statusJson() => {
        'installed': true,
        'schemaVersion': schemaVersion,
        'initialized': _initialized,
        'debugOnly': true,
        'config': _config.toJson(),
        'counts': {
          'events': _events.length,
          'providers': _providers.length,
          'routes': _routes.length,
          'logs': _logs.length,
          'network': _network.length,
          'rebuilds': _rebuilds.length,
          'errors': _errors.length,
        },
        'latestEventId': _nextEventId - 1,
        'errorHooksInstalled': _errorHooksInstalled,
      };

  Map<String, Object?> _snapshotJson() => {
        'schemaVersion': schemaVersion,
        'status': _statusJson(),
        'current': {
          'providers': _providerState,
          'route': _routeState,
        },
        'providers':
            _providers.toList().map((event) => event.toJson()).toList(),
        'routes': _routes.toList().map((event) => event.toJson()).toList(),
        'logs': _logs.toList().map((event) => event.toJson()).toList(),
        'network': _network.toList().map((event) => event.toJson()).toList(),
        'rebuilds': _rebuilds.toList().map((event) => event.toJson()).toList(),
        'errors': _errors.toList().map((event) => event.toJson()).toList(),
      };

  Map<String, Object?> _diagnosticsJson() {
    final errors = _errors.toList();
    final failedNetwork = _network
        .where((event) {
          final statusCode = event.data['statusCode'];
          return event.severity == 'error' ||
              (statusCode is int && statusCode >= 400);
        })
        .map((event) => event.toJson())
        .toList();
    final rebuilds = List<AgentEvent>.of(_rebuilds.toList())
      ..sort(
        (a, b) => ((b.data['count'] as int?) ?? 0).compareTo(
          (a.data['count'] as int?) ?? 0,
        ),
      );
    return {
      'schemaVersion': 'agent-runtime.diagnostics.v1',
      'status': _statusJson(),
      'currentRoute': _routeState,
      'providerCount': _providerState.length,
      'recentProviderChanges': _providers
          .toList()
          .reversed
          .take(20)
          .map((event) => event.toJson())
          .toList(),
      'latestErrors':
          errors.reversed.take(10).map((event) => event.toJson()).toList(),
      'failedNetworkRequests': failedNetwork.reversed.take(10).toList(),
      'topRebuildHotspots':
          rebuilds.take(20).map((event) => event.toJson()).toList(),
      'recentLogs': _logs
          .toList()
          .reversed
          .take(20)
          .map((event) => event.toJson())
          .toList(),
    };
  }

  Map<String, Object?> _serializeMap(Map<String, Object?> value) {
    return value.map(
      (key, mapValue) => MapEntry(key, _serializer.serialize(mapValue)),
    );
  }

  Map<String, Object?> _redactHeaders(Map<String, Object?> headers) {
    return headers.map((key, value) {
      final normalized = _normalizeSensitiveKey(key);
      final redacted = _config.redactedHeaderNames.any(
        (header) => _normalizeSensitiveKey(header) == normalized,
      );
      if (redacted) {
        return MapEntry(key, '<redacted>');
      }
      return MapEntry(key, _serializer.serialize(value));
    });
  }

  String _normalizeSensitiveKey(String key) {
    return key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  Map<String, Object?> _errorJson(Object error, StackTrace? stackTrace) => {
        'type': error.runtimeType.toString(),
        'message': error.toString(),
        if (stackTrace != null) 'stackTrace': stackTrace.toString(),
      };

  String _jsonString(Object? value) => jsonEncode(value);
}
