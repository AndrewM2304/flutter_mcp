import 'package:flutter/widgets.dart';
import 'package:flutter_agent_runtime/flutter_agent_runtime.dart';
import 'package:go_router/go_router.dart';

class AgentGoRouterObserver extends NavigatorObserver {
  AgentGoRouterObserver({this.source = 'go_router'});

  final String source;

  String? _current(Route<dynamic>? route) {
    if (route == null) return null;
    return route.settings.name ?? route.settings.toString();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record('push', route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record('pop', previousRoute, route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record('remove', previousRoute, route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _record('replace', newRoute, oldRoute);
  }

  @override
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    _record('startUserGesture', route, previousRoute);
  }

  @override
  void didStopUserGesture() {
    AgentRuntime.instance.recordRouteEvent(
      action: 'stopUserGesture',
      source: source,
    );
  }

  void recordRedirect({
    required String from,
    required String to,
    String? reason,
  }) {
    AgentRuntime.instance.recordRouteEvent(
      action: 'redirect',
      location: to,
      previousLocation: from,
      source: source,
      attributes: {if (reason != null) 'reason': reason},
    );
  }

  void recordGoRouterRedirect({
    required GoRouterState state,
    required String? targetLocation,
    String? reason,
  }) {
    AgentRuntime.instance.recordRouteEvent(
      action: 'redirect',
      location: targetLocation,
      previousLocation: state.uri.toString(),
      source: source,
      attributes: _stateAttributes(state)
        ..addAll({
          if (reason != null) 'reason': reason,
        }),
    );
  }

  void recordRouterError(
    Object error,
    StackTrace stackTrace, {
    String? location,
  }) {
    AgentRuntime.instance.recordRouteEvent(
      action: 'error',
      location: location,
      error: error,
      stackTrace: stackTrace,
      source: source,
    );
  }

  void recordGoRouterError(
    Object error,
    StackTrace stackTrace, {
    required GoRouterState state,
  }) {
    AgentRuntime.instance.recordRouteEvent(
      action: 'error',
      location: state.uri.toString(),
      error: error,
      stackTrace: stackTrace,
      source: source,
      attributes: _stateAttributes(state),
    );
  }

  void _record(
    String action,
    Route<dynamic>? route,
    Route<dynamic>? previousRoute,
  ) {
    AgentRuntime.instance.recordRouteEvent(
      action: action,
      location: _current(route),
      previousLocation: _current(previousRoute),
      source: source,
      stack: [
        if (_current(previousRoute) != null) _current(previousRoute)!,
        if (_current(route) != null) _current(route)!,
      ],
      attributes: {
        if (route?.settings.arguments != null)
          'arguments': route!.settings.arguments,
      },
    );
  }

  Map<String, Object?> _stateAttributes(GoRouterState state) => {
        'matchedLocation': state.matchedLocation,
        'fullPath': state.fullPath,
        'pathParameters': state.pathParameters,
        'queryParameters': state.uri.queryParameters,
        if (state.name != null) 'name': state.name,
      };
}
