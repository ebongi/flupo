import 'package:flupo/src/patch/ios_identifier_patcher.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

void main() {
  final before = readFixture('project_pbxproj_before.txt');

  test(
    'replaces all Runner and RunnerTests occurrences from the real baseline',
    () {
      final result = patchPbxprojBundleIdentifier(before, 'com.acme.myapp');

      expect(result.changed, isTrue);
      expect(result.previousIdentifier, 'com.example.flupoGo');
      expect(result.sanitizedIdentifier, 'com.acme.myapp');
      expect(
        'PRODUCT_BUNDLE_IDENTIFIER = com.acme.myapp;'
            .allMatches(result.content)
            .length,
        3,
      );
      expect(
        'PRODUCT_BUNDLE_IDENTIFIER = com.acme.myapp.RunnerTests;'
            .allMatches(result.content)
            .length,
        3,
      );
      expect(result.content, isNot(contains('flupoGo')));
    },
  );

  test('sanitizes underscores out of the identifier and warns', () {
    final result = patchPbxprojBundleIdentifier(before, 'com.example.flupo_go');

    expect(result.sanitizedIdentifier, 'com.example.flupogo');
    expect(result.warning, contains('cannot contain underscores'));
    expect(
      result.content,
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.example.flupogo;'),
    );
  });

  test('is a no-op when the sanitized identifier already matches', () {
    final result = patchPbxprojBundleIdentifier(before, 'com.example.flupoGo');

    expect(result.changed, isFalse);
    expect(result.content, before);
  });

  test('warns and skips when no PRODUCT_BUNDLE_IDENTIFIER is found', () {
    final result = patchPbxprojBundleIdentifier('{ }', 'com.acme.myapp');

    expect(result.changed, isFalse);
    expect(result.warning, contains('No PRODUCT_BUNDLE_IDENTIFIER'));
  });

  test('warns and skips when Runner targets disagree on their identifier', () {
    const ambiguous = '''
PRODUCT_BUNDLE_IDENTIFIER = com.example.appA;
PRODUCT_BUNDLE_IDENTIFIER = com.example.appB;
PRODUCT_BUNDLE_IDENTIFIER = com.example.appA.RunnerTests;
''';

    final result = patchPbxprojBundleIdentifier(ambiguous, 'com.acme.myapp');

    expect(result.changed, isFalse);
    expect(
      result.warning,
      contains('Could not determine a single Runner target'),
    );
  });

  test('is idempotent: patching twice matches patching once', () {
    final first = patchPbxprojBundleIdentifier(before, 'com.acme.myapp');
    final second = patchPbxprojBundleIdentifier(
      first.content,
      'com.acme.myapp',
    );

    expect(second.changed, isFalse);
    expect(second.content, first.content);
  });
}
