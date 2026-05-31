import 'package:flutter_agent_runtime/flutter_agent_runtime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AgentProviderObserver extends ProviderObserver {
  const AgentProviderObserver({this.source = 'riverpod'});

  final String source;

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    AgentRuntime.instance.recordProviderEvent(
      action: 'add',
      provider: _providerName(provider),
      providerType: provider.runtimeType.toString(),
      nextValue: value,
      source: source,
    );
  }

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    AgentRuntime.instance.recordProviderEvent(
      action: 'update',
      provider: _providerName(provider),
      providerType: provider.runtimeType.toString(),
      previousValue: previousValue,
      nextValue: newValue,
      source: source,
    );
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    AgentRuntime.instance.recordProviderEvent(
      action: 'dispose',
      provider: _providerName(provider),
      providerType: provider.runtimeType.toString(),
      source: source,
    );
  }

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    AgentRuntime.instance.recordProviderEvent(
      action: 'error',
      provider: _providerName(provider),
      providerType: provider.runtimeType.toString(),
      error: error,
      stackTrace: stackTrace,
      source: source,
    );
  }

  String _providerName(ProviderBase<Object?> provider) {
    return provider.name ?? provider.runtimeType.toString();
  }
}
