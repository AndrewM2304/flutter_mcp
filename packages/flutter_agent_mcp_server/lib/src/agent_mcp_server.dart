import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'json_rpc_stdio.dart';
import 'vm_service_client.dart';

class AgentMcpServer {
  AgentMcpServer(Stream<List<int>> input, IOSink output)
      : _rpc = JsonRpcStdio(input, output);

  final JsonRpcStdio _rpc;
  VmServiceClient? _client;
  String? _workspaceRoot;
  String? _lastUri;
  String? _lastWorkspaceRoot;
  _FlowRecording? _activeFlow;
  final File _logFile = File('.dart_tool/flutter_agent_mcp_server.log');

  Future<void> run() async {
    _log('server started; waiting for MCP client messages');
    final inputTask = _rpc.start();
    await for (final message in _rpc.messages) {
      await _handle(message);
    }
    _log('stdin closed; server stopping');
    await inputTask;
  }

  Future<void> _handle(Map<String, Object?> message) async {
    final id = message['id'];
    final method = message['method'] as String?;
    if (method == null) return;

    if (id == null && method.startsWith('notifications/')) {
      _log('received $method notification');
      return;
    }

    try {
      if (method != 'tools/call') {
        _log('received $method request');
      }
      final result = switch (method) {
        'initialize' => _initialize(message['params']),
        'tools/list' => _toolsList(),
        'tools/call' => await _toolsCall(message['params']),
        'prompts/list' => _promptsList(),
        'prompts/get' => _promptsGet(message['params']),
        'ping' => <String, Object?>{},
        _ => throw McpException(-32601, 'Method not found: $method'),
      };
      if (id != null) {
        _rpc.send({'jsonrpc': '2.0', 'id': id, 'result': result});
      }
    } on McpException catch (error) {
      _log('request failed: ${error.message}');
      if (id != null) {
        _rpc.send({
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': error.code, 'message': error.message},
        });
      }
    } catch (error) {
      _log('request failed: $error');
      if (id != null) {
        _rpc.send({
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': -32603, 'message': error.toString()},
        });
      }
    }
  }

  Map<String, Object?> _initialize(Object? params) {
    var protocolVersion = '2024-11-05';
    if (params is Map) {
      final requested = params['protocolVersion'] as String?;
      if (requested != null && requested.isNotEmpty) {
        protocolVersion = requested;
      }
    }
    return {
      'protocolVersion': protocolVersion,
      'serverInfo': {'name': 'flutter_agent_mcp_server', 'version': '0.1.0'},
      'capabilities': {
        'tools': <String, Object?>{},
        'prompts': <String, Object?>{},
      },
    };
  }

  Map<String, Object?> _toolsList() => {
        'tools': _tools.map((tool) => tool.toJson()).toList(),
      };

  Map<String, Object?> _promptsList() => {
        'prompts': _prompts.map((prompt) => prompt.toJson()).toList(),
      };

  Map<String, Object?> _promptsGet(Object? params) {
    if (params is! Map) {
      throw McpException(-32602, 'prompts/get params must be an object.');
    }
    final name = params['name'] as String?;
    if (name == null) {
      throw McpException(-32602, 'prompts/get requires a name.');
    }
    _Prompt? prompt;
    for (final candidate in _prompts) {
      if (candidate.name == name) {
        prompt = candidate;
        break;
      }
    }
    if (prompt == null) {
      throw McpException(-32602, 'Unknown prompt: $name');
    }
    final arguments = params['arguments'] is Map
        ? Map<String, Object?>.from(params['arguments'] as Map)
        : <String, Object?>{};
    return prompt.response(arguments);
  }

  Future<Map<String, Object?>> _toolsCall(Object? params) async {
    if (params is! Map) {
      throw McpException(-32602, 'tools/call params must be an object.');
    }
    final name = params['name'] as String?;
    final arguments = params['arguments'] is Map
        ? Map<String, Object?>.from(params['arguments'] as Map)
        : <String, Object?>{};
    if (name == null) {
      throw McpException(-32602, 'tools/call requires a name.');
    }

    final sw = Stopwatch()..start();
    _log('tool started: $name');
    final result = await _callTool(name, arguments);
    _log(
      'tool finished: $name '
      'ok=${result['ok'] != false} '
      'elapsed=${sw.elapsedMilliseconds}ms',
    );
    return {
      'content': [
        {
          'type': 'text',
          'text': const JsonEncoder.withIndent('  ').convert(result),
        },
      ],
      'isError': result['ok'] == false,
    };
  }

  Future<Map<String, Object?>> _callTool(
    String name,
    Map<String, Object?> arguments,
  ) async {
    switch (name) {
      case 'connect_to_app':
        return _connect(arguments);
      case 'connect_and_diagnose':
        return _connectAndDiagnose(arguments);
      case 'reconnect_last':
        return _reconnectLast();
      case 'connection_status':
        return _connectionStatus();
      case 'disconnect':
        await _stopFlowRebuildTracking();
        await _client?.close();
        _client = null;
        _activeFlow = null;
        return {'ok': true, 'connected': false};
      case 'get_app_info':
        return _getAppInfo();
      case 'flutter_status':
        return _runtimeExtension('ext.agentRuntime.status');
      case 'flutter_snapshot':
        return _runtimeExtension('ext.agentRuntime.snapshot');
      case 'flutter_events':
        return _runtimeExtension('ext.agentRuntime.events', args: arguments);
      case 'flutter_diagnostics_bundle':
        return _diagnosticsBundle(arguments);
      case 'riverpod_state':
        return _stateWithEvents(
          currentSection: 'providers',
          eventType: 'provider',
          arguments: arguments,
        );
      case 'go_router_state':
        return _stateWithEvents(
          currentSection: 'route',
          eventType: 'route',
          arguments: arguments,
        );
      case 'app_logs':
        return _typedEvents('log', arguments);
      case 'network_requests':
        return _typedEvents('network', arguments);
      case 'agent_runtime_configure':
        return _runtimeExtension('ext.agentRuntime.configure', args: arguments);
      case 'widget_rebuilds':
        return _widgetRebuilds(arguments);
      case 'mcp_activity_log':
        return _activityLog(arguments);
      case 'start_flow_recording':
        return _startFlowRecording(arguments);
      case 'stop_flow_recording':
        return _stopFlowRecording(arguments);
      case 'flow_recording_status':
        return _flowRecordingStatus();
      case 'diagnose_current_screen':
        return _diagnoseCurrentScreen(arguments);
      case 'investigate_latest_error':
        return _investigateLatestError();
      case 'trace_navigation_issue':
        return _traceNavigationIssue();
      case 'check_runtime_integration':
        return _checkRuntimeIntegration();
      default:
        throw McpException(-32602, 'Unknown tool: $name');
    }
  }

  Future<Map<String, Object?>> _connect(Map<String, Object?> arguments) async {
    final uri = (arguments['uri'] ?? arguments['vmServiceUri']) as String?;
    if (uri == null || uri.trim().isEmpty) {
      throw McpException(
        -32602,
        'connect_to_app requires uri or vmServiceUri.',
      );
    }
    _workspaceRoot = arguments['workspace_root'] as String?;
    _lastUri = uri.trim();
    _lastWorkspaceRoot = _workspaceRoot;
    await _stopFlowRebuildTracking();
    await _client?.close();
    _activeFlow = null;
    _log('connecting to Flutter VM Service: $uri');
    _client = await VmServiceClient.connect(uri);
    final appInfo = await _getAppInfo();
    _log('connected to Flutter app; workspace=$_workspaceRoot');
    return {
      'ok': true,
      'connected': true,
      'workspaceRoot': _workspaceRoot,
      'app': appInfo,
    };
  }

  Future<Map<String, Object?>> _connectAndDiagnose(
    Map<String, Object?> arguments,
  ) async {
    final connect = await _connect(arguments);
    if (connect['ok'] != true) {
      return connect;
    }
    final diagnostics = await _diagnosticsBundle(arguments);
    return {
      'ok': diagnostics['ok'] == true,
      'connected': true,
      'connection': connect,
      'diagnostics': diagnostics['data'] ?? diagnostics,
      if (diagnostics['ok'] == false) 'diagnosticsError': diagnostics,
    };
  }

  Future<Map<String, Object?>> _reconnectLast() async {
    final uri = _lastUri;
    if (uri == null || uri.isEmpty) {
      return {
        'ok': false,
        'reason': 'no_last_connection',
        'message': 'No previous connection. Call connect_to_app first.',
      };
    }
    return _connect({
      'uri': uri,
      if (_lastWorkspaceRoot != null) 'workspace_root': _lastWorkspaceRoot,
    });
  }

  Map<String, Object?> _connectionStatus() {
    final client = _client;
    if (client == null) {
      return {
        'ok': true,
        'connected': false,
        if (_lastUri != null) 'lastUri': _lastUri,
        if (_lastWorkspaceRoot != null) 'lastWorkspaceRoot': _lastWorkspaceRoot,
      };
    }
    return {
      'ok': true,
      'connected': true,
      'workspaceRoot': _workspaceRoot,
      'lastUri': _lastUri,
      'lastWorkspaceRoot': _lastWorkspaceRoot,
    };
  }

  Future<Map<String, Object?>> _diagnosticsBundle(
    Map<String, Object?> arguments,
  ) async {
    final missing = _notConnectedResult();
    if (missing != null) {
      return missing;
    }
    final summary = arguments['summary'] == true ||
        arguments['summary']?.toString().toLowerCase() == 'true';
    return _runtimeExtension(
      'ext.agentRuntime.diagnostics',
      args: summary ? {'summary': 'true'} : const {},
    );
  }

  Map<String, Object?>? _notConnectedResult() {
    if (_client != null) {
      return null;
    }
    return {
      'ok': false,
      'reason': 'not_connected',
      'message': 'Call connect_to_app or connect_and_diagnose first.',
      if (_lastUri != null) 'lastUri': _lastUri,
      if (_lastWorkspaceRoot != null) 'lastWorkspaceRoot': _lastWorkspaceRoot,
    };
  }

  Future<Map<String, Object?>> _getAppInfo() async {
    final missing = _notConnectedResult();
    if (missing != null) {
      return missing;
    }
    final client = _requireClient();
    final vm = await client.getVm();
    final isolate = await client.getIsolate();
    return {
      'ok': true,
      'vm': {'name': vm['name'], 'version': vm['version']},
      'isolate': {
        'id': isolate['id'],
        'name': isolate['name'],
        'runnable': isolate['runnable'],
        'extensionRPCs': isolate['extensionRPCs'] ?? const [],
      },
      'capabilities': _capabilities(isolate),
    };
  }

  Future<Map<String, Object?>> _typedEvents(
    String type,
    Map<String, Object?> arguments,
  ) {
    return _runtimeExtension(
      'ext.agentRuntime.events',
      args: {...arguments, 'type': type},
    );
  }

  Future<Map<String, Object?>> _stateWithEvents({
    required String currentSection,
    required String eventType,
    required Map<String, Object?> arguments,
  }) async {
    final snapshot = await _runtimeExtension('ext.agentRuntime.snapshot');
    final events = await _typedEvents(eventType, arguments);
    final data = snapshot['data'];
    final currentData = data is Map ? data['current'] : null;
    final current = currentData is Map ? currentData[currentSection] : null;
    return {
      'ok': snapshot['ok'] == true && events['ok'] == true,
      'current': current,
      'events': events['data'],
      if (snapshot['ok'] == false) 'snapshotError': snapshot,
      if (events['ok'] == false) 'eventsError': events,
    };
  }

  Future<Map<String, Object?>> _runtimeExtension(
    String extension, {
    Map<String, Object?> args = const {},
  }) async {
    final missing = _notConnectedResult();
    if (missing != null) {
      return missing;
    }
    final client = _requireClient();
    final isolate = await client.getIsolate();
    final extensions =
        (isolate['extensionRPCs'] as List?)?.cast<Object?>() ?? const [];
    if (!extensions.contains(extension)) {
      _log('runtime extension missing: $extension');
      return {
        'ok': false,
        'reason': 'instrumentation_missing',
        'message': 'App runtime extension is not available: $extension',
        'availableExtensions': extensions,
      };
    }
    _log('calling runtime extension: $extension');
    final raw = await client.callServiceExtension(extension, args: args);
    return {
      'ok': true,
      'extension': extension,
      'data': _unwrapExtensionResult(raw),
    };
  }

  Future<Map<String, Object?>> _widgetRebuilds(
    Map<String, Object?> arguments,
  ) async {
    final missing = _notConnectedResult();
    if (missing != null) {
      return missing;
    }
    final client = _requireClient();
    final durationSeconds =
        ((arguments['duration_seconds'] as num?) ?? 3).toInt();
    _log('rebuild sampling requested: ${durationSeconds}s');
    final isolate = await client.getIsolate();
    final extensions =
        (isolate['extensionRPCs'] as List?)?.cast<Object?>() ?? const [];
    if (!extensions.contains(
      'ext.flutter.inspector.trackRebuildDirtyWidgets',
    )) {
      return {
        'ok': false,
        'reason': 'flutter_inspector_unavailable',
        'message': 'Widget rebuild tracking requires a debug-mode Flutter app.',
        'availableExtensions': extensions,
      };
    }

    final idToName = <String, String>{};
    final idToLocation = <String, String>{};
    _log('loading widget location map');
    await _seedWidgetLocations(client, idToName, idToLocation);

    final events = <Map<String, Object?>>[];
    late StreamSubscription<Map<String, Object?>> sub;
    try {
      try {
        await client.streamListen('Extension');
      } catch (_) {
        // The VM reports an error if the stream is already subscribed.
      }
      sub = client.extensionEvents.listen((event) {
        if (event['extensionKind'] == 'Flutter.RebuiltWidgets') {
          final data = event['extensionData'];
          if (data is Map) {
            final payload = Map<String, Object?>.from(
              data['data'] as Map? ?? data,
            );
            _parseLocations(payload['locations'], idToName, idToLocation);
            _parseNewLocations(payload['newLocations'], idToLocation);
            events.add(payload);
          }
        }
      });
      await client.callServiceExtension(
        'ext.flutter.inspector.trackRebuildDirtyWidgets',
        args: {'enabled': true},
      );
      _log('rebuild tracking enabled; interact with the app now');
      await Future<void>.delayed(
        Duration(seconds: durationSeconds.clamp(1, 30)),
      );
      await client.callServiceExtension(
        'ext.flutter.inspector.trackRebuildDirtyWidgets',
        args: {'enabled': false},
      );
      _log('rebuild tracking disabled');
    } finally {
      await sub.cancel();
    }

    final counts = <String, int>{};
    for (final event in events) {
      final rebuildEvents = event['events'];
      if (rebuildEvents is List) {
        for (var i = 0; i + 1 < rebuildEvents.length; i += 2) {
          final id = rebuildEvents[i].toString();
          final count =
              rebuildEvents[i + 1] is int ? rebuildEvents[i + 1] as int : 1;
          counts[id] = (counts[id] ?? 0) + count;
        }
      }
    }
    final rebuilds = counts.entries
        .map(
          (entry) => {
            'id': entry.key,
            'widget': idToName[entry.key] ?? 'Widget#${entry.key}',
            'location': _resolveWorkspacePath(
              idToLocation[entry.key] ?? 'unknown',
            ),
            'count': entry.value,
          },
        )
        .toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    await _storeRebuildSummaries(client, rebuilds, durationSeconds);
    _log(
      'rebuild sample complete: rawEvents=${events.length} '
      'widgets=${rebuilds.length}',
    );

    return {
      'ok': true,
      'durationSeconds': durationSeconds,
      'rawEvents': events.length,
      'rebuilds': rebuilds,
    };
  }

  Future<Map<String, Object?>> _startFlowRecording(
    Map<String, Object?> arguments,
  ) async {
    final missing = _notConnectedResult();
    if (missing != null) {
      return missing;
    }
    if (_activeFlow != null) {
      return {
        'ok': false,
        'reason': 'flow_already_active',
        'message':
            'A flow recording is already active. Stop it before starting another.',
        'activeFlow': _activeFlow!.toStatusJson(),
      };
    }

    final status = await _runtimeExtension('ext.agentRuntime.status');
    if (status['ok'] == false) {
      return status;
    }
    final snapshot = await _runtimeExtension('ext.agentRuntime.snapshot');
    if (snapshot['ok'] == false) {
      return snapshot;
    }
    final statusData = status['data'];
    final startEventId = statusData is Map && statusData['latestEventId'] is int
        ? statusData['latestEventId'] as int
        : -1;
    final snapshotData = snapshot['data'];
    final current = snapshotData is Map ? snapshotData['current'] : null;
    final currentMap = current is Map
        ? Map<String, Object?>.from(current)
        : <String, Object?>{};
    final label = arguments['label']?.toString().trim();
    final flow = _FlowRecording(
      label: label == null || label.isEmpty ? null : label,
      startEventId: startEventId,
      startedAt: DateTime.now(),
      baseline: currentMap,
    );
    _activeFlow = flow;

    final trackRebuilds = arguments['track_rebuilds'] == true ||
        arguments['trackRebuilds'] == true ||
        arguments['track_rebuilds']?.toString().toLowerCase() == 'true' ||
        arguments['trackRebuilds']?.toString().toLowerCase() == 'true';
    if (trackRebuilds) {
      flow.rebuildTracking = await _startFlowRebuildTracking();
    }

    _log(
      'flow recording started: label=${flow.label ?? '(none)'} '
      'startEventId=${flow.startEventId}',
    );
    return {
      'ok': true,
      'recording': flow.toStatusJson(),
      'message':
          'Flow recording started. Use the app, then call stop_flow_recording.',
    };
  }

  Future<Map<String, Object?>> _stopFlowRecording(
    Map<String, Object?> arguments,
  ) async {
    final flow = _activeFlow;
    if (flow == null) {
      return {
        'ok': false,
        'reason': 'no_active_flow',
        'message':
            'No flow recording is active. Call start_flow_recording first.',
      };
    }
    final missing = _notConnectedResult();
    if (missing != null) {
      return missing;
    }
    _activeFlow = null;
    final rebuildTracking = await _stopFlowRebuildTracking(flow);
    final summary = arguments['summary'] == true ||
        arguments['summary']?.toString().toLowerCase() == 'true';
    final events = await _eventsSince(flow.startEventId);
    final diagnostics = await _diagnosticsBundle({'summary': summary});
    final diagnosticsData = diagnostics['data'];
    final eventGroups = _partitionEvents(events);
    final failedNetwork = _failedNetwork(eventGroups['network'] ?? const []);
    final suspiciousLogs = _suspiciousLogs(eventGroups['log'] ?? const []);
    final topRebuilds = _topRebuilds([
      ...(eventGroups['rebuild'] ?? const <Map<String, Object?>>[]),
      ...rebuildTracking.rebuilds,
    ]);
    final currentRoute =
        diagnosticsData is Map ? diagnosticsData['currentRoute'] : null;
    final currentProviders =
        diagnosticsData is Map ? diagnosticsData['currentProviders'] : null;
    final report = {
      'label': flow.label,
      'startedAt': flow.startedAt.toIso8601String(),
      'stoppedAt': DateTime.now().toIso8601String(),
      'startEventId': flow.startEventId,
      'eventCount': events.length,
      'counts': eventGroups.map((key, value) => MapEntry(key, value.length)),
      'currentRoute': currentRoute,
      'baselineRoute': flow.baseline['route'],
      'currentProviders': currentProviders,
      'baselineProviders': flow.baseline['providers'],
      'latestErrors': eventGroups['error'] ?? const <Map<String, Object?>>[],
      'failedNetworkRequests': failedNetwork,
      'suspiciousLogs': suspiciousLogs,
      'topRebuildHotspots': topRebuilds,
      'rebuildTracking': rebuildTracking.toJson(),
    };
    _log(
      'flow recording stopped: label=${flow.label ?? '(none)'} '
      'events=${events.length}',
    );
    return {
      'ok': true,
      'recording': flow.toStatusJson(active: false),
      'report': report,
      'events': eventGroups,
      if (diagnostics['ok'] == false) 'diagnosticsError': diagnostics,
    };
  }

  Map<String, Object?> _flowRecordingStatus() {
    final flow = _activeFlow;
    return {
      'ok': true,
      'active': flow != null,
      if (flow != null) 'recording': flow.toStatusJson(),
    };
  }

  Future<Map<String, Object?>> _diagnoseCurrentScreen(
    Map<String, Object?> arguments,
  ) async {
    final missing = _notConnectedResult();
    if (missing != null) {
      return missing;
    }
    final diagnostics = await _diagnosticsBundle({
      'summary': arguments['summary'] ?? true,
    });
    if (diagnostics['ok'] == false) {
      return diagnostics;
    }
    return {
      'ok': true,
      'workflow': 'diagnose_current_screen',
      'diagnostics': diagnostics['data'],
    };
  }

  Future<Map<String, Object?>> _investigateLatestError() async {
    final missing = _notConnectedResult();
    if (missing != null) {
      return missing;
    }
    final diagnostics = await _diagnosticsBundle({'summary': true});
    if (diagnostics['ok'] == false) {
      return diagnostics;
    }
    final data = diagnostics['data'];
    final errors = data is Map && data['latestErrors'] is List
        ? (data['latestErrors'] as List).whereType<Map>().toList()
        : const <Map>[];
    return {
      'ok': true,
      'workflow': 'investigate_latest_error',
      'latestError': errors.isEmpty ? null : errors.first,
      'currentRoute': data is Map ? data['currentRoute'] : null,
      'currentProviders': data is Map ? data['currentProviders'] : null,
      'failedNetworkRequests':
          data is Map ? data['failedNetworkRequests'] : null,
      'recentLogs': data is Map ? data['recentLogs'] : null,
      'diagnostics': data,
    };
  }

  Future<Map<String, Object?>> _traceNavigationIssue() async {
    final missing = _notConnectedResult();
    if (missing != null) {
      return missing;
    }
    final routeState = await _stateWithEvents(
      currentSection: 'route',
      eventType: 'route',
      arguments: {'limit': 100},
    );
    return {
      'ok': routeState['ok'] == true,
      'workflow': 'trace_navigation_issue',
      'currentRoute': routeState['current'],
      'routeEvents': routeState['events'],
      if (routeState['ok'] == false) 'error': routeState,
    };
  }

  Future<Map<String, Object?>> _checkRuntimeIntegration() async {
    final appInfo = await _getAppInfo();
    if (appInfo['ok'] == false) {
      return appInfo;
    }
    final status = await _runtimeExtension('ext.agentRuntime.status');
    final diagnostics = await _diagnosticsBundle({'summary': true});
    return {
      'ok': true,
      'workflow': 'check_runtime_integration',
      'app': appInfo,
      'runtimeStatus': status['data'] ?? status,
      'diagnostics': diagnostics['data'] ?? diagnostics,
      'adapters': _adapterSignals(diagnostics['data']),
    };
  }

  Future<List<Map<String, Object?>>> _eventsSince(int startEventId) async {
    final events = <Map<String, Object?>>[];
    var cursor = startEventId;
    while (true) {
      final result = await _runtimeExtension(
        'ext.agentRuntime.events',
        args: {'since': cursor, 'limit': 500},
      );
      if (result['ok'] == false) break;
      final data = result['data'];
      final page = data is Map && data['events'] is List
          ? (data['events'] as List)
              .whereType<Map>()
              .map((event) => Map<String, Object?>.from(event))
              .toList()
          : <Map<String, Object?>>[];
      events.addAll(page);
      if (page.length < 500) break;
      final nextCursor = data is Map ? data['nextCursor'] : null;
      if (nextCursor is int && nextCursor > cursor) {
        cursor = nextCursor;
      } else {
        break;
      }
    }
    return events;
  }

  Map<String, List<Map<String, Object?>>> _partitionEvents(
    List<Map<String, Object?>> events,
  ) {
    final groups = <String, List<Map<String, Object?>>>{
      'provider': [],
      'route': [],
      'log': [],
      'network': [],
      'rebuild': [],
      'error': [],
      'other': [],
    };
    for (final event in events) {
      final type = event['type']?.toString();
      if (type != null && groups.containsKey(type)) {
        groups[type]!.add(event);
      } else {
        groups['other']!.add(event);
      }
      if (event['severity'] == 'error' && type != 'error') {
        groups['error']!.add(event);
      }
    }
    return groups;
  }

  List<Map<String, Object?>> _failedNetwork(List<Map<String, Object?>> events) {
    return events.where((event) {
      final data = event['data'];
      final statusCode = data is Map ? data['statusCode'] : null;
      return event['severity'] == 'error' ||
          (statusCode is int && statusCode >= 400);
    }).toList();
  }

  List<Map<String, Object?>> _suspiciousLogs(
      List<Map<String, Object?>> events) {
    return events.where((event) {
      final severity = event['severity']?.toString().toLowerCase();
      if (severity == 'error' || severity == 'warning' || severity == 'warn') {
        return true;
      }
      final text = jsonEncode(event).toLowerCase();
      return text.contains('error') ||
          text.contains('exception') ||
          text.contains('fail');
    }).toList();
  }

  List<Map<String, Object?>> _topRebuilds(List<Map<String, Object?>> events) {
    final sorted = List<Map<String, Object?>>.from(events)
      ..sort((a, b) {
        return _eventCount(b).compareTo(_eventCount(a));
      });
    return sorted.take(20).toList();
  }

  int _eventCount(Map<String, Object?> event) {
    final direct = event['count'];
    if (direct is num) return direct.toInt();
    final data = event['data'];
    final nested = data is Map ? data['count'] : null;
    if (nested is num) return nested.toInt();
    return 0;
  }

  Map<String, Object?> _adapterSignals(Object? diagnosticsData) {
    if (diagnosticsData is! Map) return const {};
    final currentProviders = diagnosticsData['currentProviders'];
    final currentRoute = diagnosticsData['currentRoute'];
    final logs = diagnosticsData['recentLogs'];
    final network = diagnosticsData['failedNetworkRequests'];
    return {
      'riverpod': currentProviders is Map && currentProviders.isNotEmpty,
      'goRouter': currentRoute != null,
      'talkerLogs': logs is List && logs.isNotEmpty,
      'networkMetadata': network is List && network.isNotEmpty,
    };
  }

  Future<_FlowRebuildTracking> _startFlowRebuildTracking() async {
    final client = _requireClient();
    final isolate = await client.getIsolate();
    final extensions =
        (isolate['extensionRPCs'] as List?)?.cast<Object?>() ?? const [];
    if (!extensions.contains(
      'ext.flutter.inspector.trackRebuildDirtyWidgets',
    )) {
      return _FlowRebuildTracking.unavailable(
        'Widget rebuild tracking requires a debug-mode Flutter app.',
      );
    }

    final tracking = _FlowRebuildTracking.active();
    await _seedWidgetLocations(
        client, tracking.idToName, tracking.idToLocation);
    try {
      await client.streamListen('Extension');
    } catch (_) {
      // The VM reports an error if the stream is already subscribed.
    }
    tracking.subscription = client.extensionEvents.listen((event) {
      if (event['extensionKind'] != 'Flutter.RebuiltWidgets') return;
      final data = event['extensionData'];
      if (data is! Map) return;
      final payload = Map<String, Object?>.from(data['data'] as Map? ?? data);
      _parseLocations(
        payload['locations'],
        tracking.idToName,
        tracking.idToLocation,
      );
      _parseNewLocations(payload['newLocations'], tracking.idToLocation);
      tracking.rawEvents.add(payload);
    });
    await client.callServiceExtension(
      'ext.flutter.inspector.trackRebuildDirtyWidgets',
      args: {'enabled': true},
    );
    _log('flow rebuild tracking enabled');
    return tracking;
  }

  Future<_FlowRebuildTracking> _stopFlowRebuildTracking([
    _FlowRecording? flow,
  ]) async {
    final target = flow ?? _activeFlow;
    final tracking = target?.rebuildTracking;
    if (tracking == null) return _FlowRebuildTracking.notRequested();
    if (!tracking.active) return tracking;
    tracking.active = false;
    try {
      final client = _client;
      if (client != null) {
        await client.callServiceExtension(
          'ext.flutter.inspector.trackRebuildDirtyWidgets',
          args: {'enabled': false},
        );
      }
    } catch (error) {
      tracking.stopError = error.toString();
    } finally {
      await tracking.subscription?.cancel();
      tracking.subscription = null;
    }
    tracking.rebuilds = _summarizeRebuildEvents(tracking);
    final client = _client;
    if (client != null) {
      await _storeRebuildSummaries(
        client,
        tracking.rebuilds,
        DateTime.now().difference(target!.startedAt).inSeconds,
      );
    }
    _log(
      'flow rebuild tracking stopped: rawEvents=${tracking.rawEvents.length} '
      'widgets=${tracking.rebuilds.length}',
    );
    return tracking;
  }

  List<Map<String, Object?>> _summarizeRebuildEvents(
    _FlowRebuildTracking tracking,
  ) {
    final counts = <String, int>{};
    for (final event in tracking.rawEvents) {
      final rebuildEvents = event['events'];
      if (rebuildEvents is! List) continue;
      for (var i = 0; i + 1 < rebuildEvents.length; i += 2) {
        final id = rebuildEvents[i].toString();
        final count =
            rebuildEvents[i + 1] is int ? rebuildEvents[i + 1] as int : 1;
        counts[id] = (counts[id] ?? 0) + count;
      }
    }
    return counts.entries
        .map(
          (entry) => {
            'id': entry.key,
            'widget': tracking.idToName[entry.key] ?? 'Widget#${entry.key}',
            'location': _resolveWorkspacePath(
              tracking.idToLocation[entry.key] ?? 'unknown',
            ),
            'count': entry.value,
          },
        )
        .toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
  }

  Future<void> _seedWidgetLocations(
    VmServiceClient client,
    Map<String, String> idToName,
    Map<String, String> idToLocation,
  ) async {
    try {
      final raw = await client.callServiceExtension(
        'ext.flutter.inspector.widgetLocationIdMap',
      );
      final result = _unwrapExtensionResult(raw);
      _parseLocations(result, idToName, idToLocation);
    } catch (_) {
      // This extension is not always available; rebuild counts are still useful.
    }
  }

  void _parseLocations(
    Object? locations,
    Map<String, String> idToName,
    Map<String, String> idToLocation,
  ) {
    if (locations is String) {
      try {
        _parseLocations(jsonDecode(locations), idToName, idToLocation);
      } catch (_) {}
      return;
    }
    if (locations is! Map) return;
    for (final entry in locations.entries) {
      final filePath = entry.key.toString();
      final value = entry.value;
      if (value is! Map) continue;
      final ids = value['ids'];
      final lines = value['lines'];
      final names = value['names'];
      if (ids is! List) continue;
      for (var index = 0; index < ids.length; index++) {
        final id = ids[index].toString();
        final line = lines is List && index < lines.length
            ? lines[index].toString()
            : '?';
        final name = names is List && index < names.length
            ? names[index]?.toString()
            : null;
        if (name != null && name.isNotEmpty) {
          idToName[id] = name;
        }
        idToLocation[id] = '$filePath:$line';
      }
    }
  }

  void _parseNewLocations(
    Object? newLocations,
    Map<String, String> idToLocation,
  ) {
    if (newLocations is! Map) return;
    for (final entry in newLocations.entries) {
      final filePath = entry.key.toString();
      final values = entry.value;
      if (values is! List) continue;
      for (var index = 0; index + 2 < values.length; index += 3) {
        final id = values[index].toString();
        final line = values[index + 1].toString();
        idToLocation.putIfAbsent(id, () => '$filePath:$line');
      }
    }
  }

  Future<void> _storeRebuildSummaries(
    VmServiceClient client,
    List<Map<String, Object?>> rebuilds,
    int durationSeconds,
  ) async {
    final isolate = await client.getIsolate();
    final extensions =
        (isolate['extensionRPCs'] as List?)?.cast<Object?>() ?? const [];
    if (!extensions.contains('ext.agentRuntime.recordRebuildSummary')) return;
    for (final rebuild in rebuilds.take(50)) {
      await client.callServiceExtension(
        'ext.agentRuntime.recordRebuildSummary',
        args: {
          'id': rebuild['id'],
          'widget': rebuild['widget'],
          'location': rebuild['location'],
          'count': rebuild['count'],
          'durationSeconds': durationSeconds,
          'source': 'mcp_widget_rebuilds',
        },
      );
    }
  }

  String _resolveWorkspacePath(String location) {
    final root = _workspaceRoot;
    if (root == null || root.isEmpty || location == 'unknown') {
      return location;
    }
    if (location.startsWith('file://')) return Uri.parse(location).toFilePath();
    if (location.startsWith('/') || location.startsWith('package:')) {
      return location;
    }
    final rootUri = Uri.directory(root);
    try {
      return rootUri.resolve(location).toFilePath();
    } catch (_) {
      return location;
    }
  }

  VmServiceClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw McpException(-32000, 'Not connected. Call connect_to_app first.');
    }
    return client;
  }

  Map<String, Object?> _activityLog(Map<String, Object?> arguments) {
    final limit = ((arguments['limit'] as num?) ?? 100).toInt().clamp(1, 1000);
    if (!_logFile.existsSync()) {
      return {
        'ok': true,
        'path': _logFile.path,
        'lines': <String>[],
      };
    }
    final lines = _logFile.readAsLinesSync();
    return {
      'ok': true,
      'path': _logFile.path,
      'lines':
          lines.length > limit ? lines.sublist(lines.length - limit) : lines,
    };
  }

  Map<String, Object?> _capabilities(Map<String, Object?> isolate) {
    final extensions =
        (isolate['extensionRPCs'] as List?)?.cast<Object?>() ?? const [];
    return {
      'agentRuntime': extensions.any(
        (extension) => extension.toString().startsWith('ext.agentRuntime.'),
      ),
      'flutterInspector': extensions.any(
        (extension) =>
            extension.toString().startsWith('ext.flutter.inspector.'),
      ),
      'rebuildTracking': extensions.contains(
        'ext.flutter.inspector.trackRebuildDirtyWidgets',
      ),
    };
  }

  Object? _unwrapExtensionResult(Map<String, Object?> raw) {
    final json = raw['json'];
    if (json is Map && json.containsKey('result')) {
      final result = json['result'];
      if (result is String) {
        return jsonDecode(result);
      }
      return result;
    }
    final result = raw['result'];
    if (result is String) {
      try {
        return jsonDecode(result);
      } catch (_) {
        return result;
      }
    }
    return result ?? raw;
  }

  void _log(String message) {
    final line =
        '${DateTime.now().toIso8601String()} [flutter_agent_mcp_server] $message';
    stderr.writeln(line);
    try {
      _logFile.parent.createSync(recursive: true);
      _logFile.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {
      // Logging must never break the MCP protocol.
    }
  }
}

class McpException implements Exception {
  McpException(this.code, this.message);

  final int code;
  final String message;
}

class _FlowRecording {
  _FlowRecording({
    required this.label,
    required this.startEventId,
    required this.startedAt,
    required this.baseline,
  });

  final String? label;
  final int startEventId;
  final DateTime startedAt;
  final Map<String, Object?> baseline;
  _FlowRebuildTracking? rebuildTracking;

  Map<String, Object?> toStatusJson({bool active = true}) => {
        'active': active,
        if (label != null) 'label': label,
        'startEventId': startEventId,
        'startedAt': startedAt.toIso8601String(),
        'elapsedSeconds': DateTime.now().difference(startedAt).inSeconds,
        'trackRebuilds': rebuildTracking != null,
        if (rebuildTracking != null)
          'rebuildTracking': rebuildTracking!.toJson(includeEvents: false),
      };
}

class _FlowRebuildTracking {
  _FlowRebuildTracking._({
    required this.requested,
    required this.available,
    required this.active,
    this.message,
  });

  factory _FlowRebuildTracking.notRequested() => _FlowRebuildTracking._(
        requested: false,
        available: false,
        active: false,
      );

  factory _FlowRebuildTracking.unavailable(String message) =>
      _FlowRebuildTracking._(
        requested: true,
        available: false,
        active: false,
        message: message,
      );

  factory _FlowRebuildTracking.active() => _FlowRebuildTracking._(
        requested: true,
        available: true,
        active: true,
      );

  final bool requested;
  final bool available;
  bool active;
  final String? message;
  String? stopError;
  StreamSubscription<Map<String, Object?>>? subscription;
  final rawEvents = <Map<String, Object?>>[];
  List<Map<String, Object?>> rebuilds = const [];
  final idToName = <String, String>{};
  final idToLocation = <String, String>{};

  Map<String, Object?> toJson({bool includeEvents = true}) => {
        'requested': requested,
        'available': available,
        'active': active,
        if (message != null) 'message': message,
        if (stopError != null) 'stopError': stopError,
        'rawEvents': rawEvents.length,
        'widgets': rebuilds.length,
        if (includeEvents) 'rebuilds': rebuilds,
      };
}

class _Tool {
  const _Tool(this.name, this.description, this.inputSchema);

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;

  Map<String, Object?> toJson() => {
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
      };
}

class _Prompt {
  const _Prompt({
    required this.name,
    required this.description,
    required this.instructions,
    this.arguments = const [],
  });

  final String name;
  final String description;
  final String Function(Map<String, Object?> arguments) instructions;
  final List<Map<String, Object?>> arguments;

  Map<String, Object?> toJson() => {
        'name': name,
        'description': description,
        if (arguments.isNotEmpty) 'arguments': arguments,
      };

  Map<String, Object?> response(Map<String, Object?> args) => {
        'description': description,
        'messages': [
          {
            'role': 'user',
            'content': {
              'type': 'text',
              'text': instructions(args),
            },
          },
        ],
      };
}

String _arg(Map<String, Object?> arguments, String name) {
  final value = arguments[name];
  if (value == null) return '';
  return value.toString().trim();
}

final _prompts = <_Prompt>[
  _Prompt(
    name: 'startFlutterRuntimeDebugger',
    description:
        'Connect to a Flutter app and show focused runtime debugging choices.',
    arguments: [
      {
        'name': 'uri',
        'description': 'Flutter VM Service or DevTools URL',
        'required': false,
      },
      {
        'name': 'workspaceRoot',
        'description': 'Absolute path to the Flutter app workspace root',
        'required': false,
      },
      {
        'name': 'goal',
        'description': 'Optional debugging goal or symptom',
        'required': false,
      },
    ],
    instructions: (args) {
      final uri = _arg(args, 'uri');
      final workspaceRoot = _arg(args, 'workspaceRoot');
      final goal = _arg(args, 'goal');
      return '''
Use the flutter-agent-runtime MCP server.

Connect to my running Flutter app and run a first diagnostic pass.

VM Service or DevTools URL: ${uri.isEmpty ? '(ask me for this)' : uri}
Workspace root: ${workspaceRoot.isEmpty ? '(ask me for this)' : workspaceRoot}
Goal: ${goal.isEmpty ? '(not specified)' : goal}

If the URL or workspace root is missing, ask only for the missing value. Once both are available, call connect_and_diagnose with summary=true.

After the diagnostic pass, give me this session workflow:
1. Start recording a session
2. Stop and review everything
3. Stop and review errors/logs
4. Stop and review network calls
5. Stop and review rebuilds
6. Stop and review provider changes
7. Stop and review navigation
8. Stop and create a bug report

Ask me to pick one or describe something else in free text. Do not use unrelated slash commands.
''';
    },
  ),
];

final _tools = <_Tool>[
  _Tool(
    'connect_and_diagnose',
    'Preferred first call: connect to a running Flutter app, then return the '
        'diagnostics bundle with currentProviders, currentRoute, errors, logs, '
        'and network metadata. Pass summary=true for a smaller payload.',
    {
      'type': 'object',
      'properties': {
        'uri': {'type': 'string'},
        'vmServiceUri': {'type': 'string'},
        'workspace_root': {'type': 'string'},
        'summary': {'type': 'boolean'},
      },
    },
  ),
  _Tool(
    'connect_to_app',
    'Connect to a running Flutter app by VM Service or DevTools URI. Saves the '
        'connection for reconnect_last. Usually prefer connect_and_diagnose '
        'instead unless you only need the connection result.',
    {
      'type': 'object',
      'properties': {
        'uri': {'type': 'string'},
        'vmServiceUri': {'type': 'string'},
        'workspace_root': {'type': 'string'},
      },
    },
  ),
  _Tool(
    'reconnect_last',
    'Reconnect using the last successful VM Service URI and workspace_root.',
    {'type': 'object'},
  ),
  _Tool(
    'connection_status',
    'Return whether the MCP server is connected and the last known URI/workspace.',
    {'type': 'object'},
  ),
  _Tool(
    'disconnect',
    'Disconnect from the current Flutter app.',
    {'type': 'object'},
  ),
  _Tool(
    'get_app_info',
    'Return VM, isolate, and extension capability info for the connected app.',
    {'type': 'object'},
  ),
  _Tool(
    'flutter_diagnostics_bundle',
    'Primary diagnostics summary after connect. Read currentProviders for live '
        'provider values and currentRoute for navigation state. Use summary=true '
        'for a smaller response. Call this before flutter_status or flutter_events.',
    {
      'type': 'object',
      'properties': {
        'summary': {'type': 'boolean'},
      },
    },
  ),
  _Tool(
    'flutter_status',
    'Return agent runtime buffer counts and install status. Secondary tool; '
        'prefer flutter_diagnostics_bundle for app state.',
    {'type': 'object'},
  ),
  _Tool(
    'flutter_snapshot',
    'Return full runtime snapshot including current providers/route and all '
        'buffer contents. Larger than flutter_diagnostics_bundle.',
    {'type': 'object'},
  ),
  _Tool(
    'flutter_events',
    'Return recent raw runtime events. Optional filters: type, since, limit. '
        'Use for timelines; prefer currentProviders for live values.',
    {
      'type': 'object',
      'properties': {
        'type': {'type': 'string'},
        'since': {'type': 'number'},
        'limit': {'type': 'number'},
      },
    },
  ),
  _Tool(
    'riverpod_state',
    'Return current provider map plus recent provider events.',
    {'type': 'object'},
  ),
  _Tool(
    'go_router_state',
    'Return current route state plus recent navigation events.',
    {'type': 'object'},
  ),
  _Tool(
    'app_logs',
    'Return recent structured Talker/runtime logs recorded by the app.',
    {'type': 'object'},
  ),
  _Tool(
    'network_requests',
    'Return recent metadata-only network requests observed by the app.',
    {'type': 'object'},
  ),
  _Tool(
    'widget_rebuilds',
    'Sample Flutter inspector rebuild events for a short window. Ask the '
        'developer to interact with the app during sampling if idle.',
    {
      'type': 'object',
      'properties': {
        'duration_seconds': {'type': 'number'},
      },
    },
  ),
  _Tool(
    'start_flow_recording',
    'Start a guided user-flow recording. The developer should use the app after '
        'this call, then call stop_flow_recording to review only new runtime '
        'events since this marker. Optional track_rebuilds enables best-effort '
        'Flutter inspector rebuild capture until stop.',
    {
      'type': 'object',
      'properties': {
        'label': {'type': 'string'},
        'track_rebuilds': {'type': 'boolean'},
        'trackRebuilds': {'type': 'boolean'},
      },
    },
  ),
  _Tool(
    'stop_flow_recording',
    'Stop the active user-flow recording and return a report with route, '
        'provider, log, error, network, and rebuild evidence from the recorded '
        'window only.',
    {
      'type': 'object',
      'properties': {
        'summary': {'type': 'boolean'},
      },
    },
  ),
  _Tool(
    'flow_recording_status',
    'Return whether a guided user-flow recording is currently active.',
    {'type': 'object'},
  ),
  _Tool(
    'diagnose_current_screen',
    'Workflow shortcut: summarize the connected app current route, live '
        'providers, latest errors, failed network requests, rebuild hotspots, '
        'and logs.',
    {
      'type': 'object',
      'properties': {
        'summary': {'type': 'boolean'},
      },
    },
  ),
  _Tool(
    'investigate_latest_error',
    'Workflow shortcut: return the latest runtime/Talker error with current '
        'route, providers, failed network requests, and nearby logs.',
    {'type': 'object'},
  ),
  _Tool(
    'trace_navigation_issue',
    'Workflow shortcut: return current route state and recent GoRouter route '
        'events for navigation or redirect investigations.',
    {'type': 'object'},
  ),
  _Tool(
    'check_runtime_integration',
    'Workflow shortcut: report VM service capabilities, agent runtime status, '
        'and whether Riverpod, GoRouter, Talker, and network signals are visible.',
    {'type': 'object'},
  ),
  _Tool(
    'mcp_activity_log',
    'Return recent MCP server log lines when VS Code output is unclear.',
    {
      'type': 'object',
      'properties': {
        'limit': {'type': 'number'},
      },
    },
  ),
  _Tool(
    'agent_runtime_configure',
    'Configure agent runtime redaction settings in the connected app.',
    {
      'type': 'object',
      'properties': {
        'redactedHeaders': {'type': 'string'},
        'redactedFields': {'type': 'string'},
        'maxSerializedStringLength': {'type': 'number'},
      },
    },
  ),
];
