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
      'capabilities': {'tools': <String, Object?>{}},
    };
  }

  Map<String, Object?> _toolsList() => {
        'tools': _tools.map((tool) => tool.toJson()).toList(),
      };

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
        await _client?.close();
        _client = null;
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
    await _client?.close();
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
