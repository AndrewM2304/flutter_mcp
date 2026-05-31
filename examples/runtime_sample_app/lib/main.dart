import 'package:flutter/material.dart';
import 'package:flutter_agent_runtime/flutter_agent_runtime.dart';
import 'package:flutter_agent_runtime_adapters/flutter_agent_runtime_adapters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final counterProvider = StateProvider<int>((ref) => 0, name: 'counterProvider');

void main() {
  AgentRuntime.init();
  AgentRuntime.installErrorHooks();
  runApp(
    const ProviderScope(
      observers: [AgentProviderObserver()],
      child: RuntimeSampleApp(),
    ),
  );
}

class RuntimeSampleApp extends ConsumerStatefulWidget {
  const RuntimeSampleApp({super.key});

  @override
  ConsumerState<RuntimeSampleApp> createState() => _RuntimeSampleAppState();
}

class _RuntimeSampleAppState extends ConsumerState<RuntimeSampleApp> {
  late final AgentGoRouterObserver routeObserver = AgentGoRouterObserver();
  late final GoRouter router = GoRouter(
    observers: [routeObserver],
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/details',
        name: 'details',
        builder: (context, state) => const DetailsScreen(),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(title: 'Runtime Sample', routerConfig: router);
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(counterProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Runtime Sample')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Count: $count'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                ref.read(counterProvider.notifier).state++;
                AgentRuntime.log(
                  'Counter incremented',
                  source: 'sample',
                  fields: {'count': ref.read(counterProvider)},
                );
              },
              child: const Text('Increment'),
            ),
            FilledButton(
              onPressed: () {
                AgentNetworkObserver.recordRequest(
                  method: 'GET',
                  url: Uri.parse('https://api.example.test/items'),
                  statusCode: 200,
                  duration: const Duration(milliseconds: 42),
                  requestHeaders: {
                    'authorization': 'secret',
                    'accept': 'application/json',
                  },
                );
              },
              child: const Text('Record Network'),
            ),
            TextButton(
              onPressed: () => context.go('/details'),
              child: const Text('Details'),
            ),
          ],
        ),
      ),
    );
  }
}

class DetailsScreen extends StatelessWidget {
  const DetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Details')),
      body: Center(
        child: TextButton(
          onPressed: () => context.go('/'),
          child: const Text('Back'),
        ),
      ),
    );
  }
}
