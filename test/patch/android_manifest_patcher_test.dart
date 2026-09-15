import 'package:flupo/src/patch/android_manifest_patcher.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

void main() {
  final before = readFixture('android_manifest_before.xml');

  test('adds a missing uses-permission element inside a managed block', () {
    final result = patchAndroidManifest(before, {
      'camera': 'Need camera access for profile photo',
    });

    expect(result.changed, isTrue);
    expect(result.added, ['android.permission.CAMERA']);
    expect(result.content, contains('<!-- flupo:managed:start -->'));
    expect(
      result.content,
      contains('<uses-permission android:name="android.permission.CAMERA"/>'),
    );
    expect(result.content, contains('<!-- flupo:managed:end -->'));
    expect(
      result.content,
      startsWith(before.substring(0, before.lastIndexOf('</manifest>'))),
    );
  });

  test('adds multiple permissions sorted, deduplicating shared strings', () {
    final result = patchAndroidManifest(before, {
      'camera': 'desc',
      'location': 'desc',
    });

    expect(result.added, [
      'android.permission.ACCESS_COARSE_LOCATION',
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.CAMERA',
    ]);
  });

  test('is a no-op when no permissions are requested', () {
    final result = patchAndroidManifest(before, {});

    expect(result.changed, isFalse);
    expect(result.content, before);
  });

  test('does not duplicate a permission the manifest already declares', () {
    final alreadyHasCamera = before.replaceFirst(
      '</manifest>',
      '    <uses-permission android:name="android.permission.CAMERA"/>\n</manifest>',
    );

    final result = patchAndroidManifest(alreadyHasCamera, {'camera': 'desc'});

    expect(result.changed, isFalse);
  });

  test('is idempotent: patching twice matches patching once', () {
    final first = patchAndroidManifest(before, {
      'camera': 'desc',
      'location': 'desc',
    });
    final second = patchAndroidManifest(first.content, {
      'camera': 'desc',
      'location': 'desc',
    });

    expect(second.changed, isFalse);
    expect(second.content, first.content);
  });
}
