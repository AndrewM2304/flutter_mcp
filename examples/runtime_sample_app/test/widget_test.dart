import 'package:flutter_agent_runtime/flutter_agent_runtime.dart';
import 'package:flutter_agent_runtime_adapters/flutter_agent_runtime_adapters.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runtime_sample_app/main.dart';

void main() {
  testWidgets('counter increments smoke test', (tester) async {
    AgentRuntime.init();

    await tester.pumpWidget(
      const ProviderScope(
        observers: [AgentProviderObserver()],
        child: RuntimeSampleApp(),
      ),
    );

    expect(find.text('Count: 0'), findsOneWidget);

    await tester.tap(find.text('Increment'));
    await tester.pump();

    expect(find.text('Count: 1'), findsOneWidget);
  });
}
