import 'package:flupo/src/patch/info_plist_patcher.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

void main() {
  final before = readFixture('info_plist_before.plist');

  test('adds a missing NS*UsageDescription pair inside a managed block', () {
    final result = patchInfoPlist(before, {
      'camera': 'Need camera access for profile photo',
    });

    expect(result.changed, isTrue);
    expect(result.added, ['NSCameraUsageDescription']);
    expect(result.content, contains('<key>NSCameraUsageDescription</key>'));
    expect(
      result.content,
      contains('<string>Need camera access for profile photo</string>'),
    );
  });

  test('escapes XML special characters in the description', () {
    final result = patchInfoPlist(before, {
      'camera': 'Fish & chips <required>',
    });

    expect(result.content, contains('Fish &amp; chips &lt;required&gt;'));
  });

  test('is a no-op when no permissions are requested', () {
    final result = patchInfoPlist(before, {});

    expect(result.changed, isFalse);
    expect(result.content, before);
  });

  test('does not duplicate a key already present at the root dict level', () {
    final alreadyHasCamera = before.replaceFirst(
      '</dict>\n</plist>',
      '\t<key>NSCameraUsageDescription</key>\n\t<string>existing</string>\n</dict>\n</plist>',
    );

    final result = patchInfoPlist(alreadyHasCamera, {
      'camera': 'new description',
    });

    expect(result.changed, isFalse);
  });

  test('is not confused by keys inside nested dicts', () {
    final result = patchInfoPlist(before, {'location': 'desc'});

    expect(result.changed, isTrue);
    expect(result.added, ['NSLocationWhenInUseUsageDescription']);
  });

  test('is idempotent: patching twice matches patching once', () {
    final first = patchInfoPlist(before, {
      'camera': 'desc',
      'location': 'desc',
    });
    final second = patchInfoPlist(first.content, {
      'camera': 'desc',
      'location': 'desc',
    });

    expect(second.changed, isFalse);
    expect(second.content, first.content);
  });
}
