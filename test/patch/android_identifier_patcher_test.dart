import 'package:flupo/src/patch/android_identifier_patcher.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

void main() {
  final before = readFixture('build_gradle_kts_before.txt');

  test('replaces the Kotlin DSL applicationId value', () {
    final result = patchAndroidApplicationId(
      before,
      isKotlinDsl: true,
      newIdentifier: 'com.acme.myapp',
    );

    expect(result.changed, isTrue);
    expect(result.previousIdentifier, 'com.example.flupo_go');
    expect(result.content, contains('applicationId = "com.acme.myapp"'));
    expect(
      result.content,
      isNot(contains('applicationId = "com.example.flupo_go"')),
    );
  });

  test('only touches applicationId, not the sibling namespace assignment', () {
    final result = patchAndroidApplicationId(
      before,
      isKotlinDsl: true,
      newIdentifier: 'com.acme.myapp',
    );

    expect(result.content, contains('namespace = "com.example.flupo_go"'));
  });

  test('is a no-op when the identifier is already correct', () {
    final result = patchAndroidApplicationId(
      before,
      isKotlinDsl: true,
      newIdentifier: 'com.example.flupo_go',
    );

    expect(result.changed, isFalse);
    expect(result.content, before);
  });

  test('reports a skip reason when no applicationId assignment is found', () {
    final result = patchAndroidApplicationId(
      'android { }',
      isKotlinDsl: true,
      newIdentifier: 'com.acme.myapp',
    );

    expect(result.changed, isFalse);
    expect(result.skippedReason, isNotNull);
  });

  test('handles the Groovy DSL syntax (no "=")', () {
    const groovy = '''
android {
    defaultConfig {
        applicationId "com.example.flupo_go"
    }
}
''';
    final result = patchAndroidApplicationId(
      groovy,
      isKotlinDsl: false,
      newIdentifier: 'com.acme.myapp',
    );

    expect(result.changed, isTrue);
    expect(result.content, contains('applicationId "com.acme.myapp"'));
  });

  test('is idempotent: patching twice matches patching once', () {
    final first = patchAndroidApplicationId(
      before,
      isKotlinDsl: true,
      newIdentifier: 'com.acme.myapp',
    );
    final second = patchAndroidApplicationId(
      first.content,
      isKotlinDsl: true,
      newIdentifier: 'com.acme.myapp',
    );

    expect(second.changed, isFalse);
    expect(second.content, first.content);
  });
}
