import 'package:flutter_agent_runtime/flutter_agent_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RingBuffer keeps only latest items', () {
    final buffer = RingBuffer<int>(3);

    buffer
      ..add(1)
      ..add(2)
      ..add(3)
      ..add(4);

    expect(buffer.toList(), [2, 3, 4]);
  });
}
