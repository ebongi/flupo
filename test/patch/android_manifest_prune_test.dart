import 'package:flupo/src/patch/android_manifest_patcher.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

void main() {
  final before = readFixture('android_manifest_before.xml');

  test('removes a managed permission no longer requested', () {
    final patched = patchAndroidManifest(before, {
      'camera': 'desc',
      'location': 'desc',
    }).content;

    final result = pruneAndroidManifest(patched, {'camera': 'desc'});

    expect(result.changed, isTrue);
    expect(result.removed, [
      'android.permission.ACCESS_COARSE_LOCATION',
      'android.permission.ACCESS_FINE_LOCATION',
    ]);
    expect(result.content, contains('android.permission.CAMERA'));
    expect(result.content, isNot(contains('ACCESS_FINE_LOCATION')));
  });

  test('drops the whole managed block once it is emptied', () {
    final patched = patchAndroidManifest(before, {'camera': 'desc'}).content;

    final result = pruneAndroidManifest(patched, {});

    expect(result.changed, isTrue);
    expect(result.removed, ['android.permission.CAMERA']);
    expect(result.content, isNot(contains('flupo:managed')));
    expect(result.content, before);
  });

  test('never touches a permission the user added by hand', () {
    final handAdded = before.replaceFirst(
      '</manifest>',
      '    <uses-permission android:name="android.permission.INTERNET"/>\n</manifest>',
    );
    final patched = patchAndroidManifest(handAdded, {'camera': 'desc'}).content;

    final result = pruneAndroidManifest(patched, {});

    expect(result.removed, ['android.permission.CAMERA']);
    expect(result.content, contains('android.permission.INTERNET'));
  });

  test('is a no-op when nothing needs removing', () {
    final patched = patchAndroidManifest(before, {'camera': 'desc'}).content;

    final result = pruneAndroidManifest(patched, {'camera': 'desc'});

    expect(result.changed, isFalse);
    expect(result.content, patched);
  });

  test('is idempotent: pruning twice matches pruning once', () {
    final patched = patchAndroidManifest(before, {
      'camera': 'desc',
      'location': 'desc',
    }).content;

    final first = pruneAndroidManifest(patched, {});
    final second = pruneAndroidManifest(first.content, {});

    expect(second.changed, isFalse);
    expect(second.content, first.content);
  });
}
