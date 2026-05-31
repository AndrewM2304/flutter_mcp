import 'package:flutter_agent_runtime/flutter_agent_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes json-safe values and summarizes unsupported values', () {
    final serializer = SafeSerializer();

    expect(serializer.serialize({'a': 1, 'b': true}), {'a': 1, 'b': true});

    final unsupported = serializer.serialize(Object());
    expect(unsupported, isA<Map<String, Object?>>());
    expect((unsupported as Map)['type'], 'Object');
  });

  test('uses custom serializers', () {
    final serializer = SafeSerializer(
      serializers: [
        (value) => value is Uri ? {'uri': value.toString()} : null,
      ],
    );

    expect(serializer.serialize(Uri.parse('https://example.com')), {
      'uri': 'https://example.com',
    });
  });
}
