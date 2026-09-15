import 'package:flupo/src/patch/info_plist_patcher.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

void main() {
  final before = readFixture('info_plist_before.plist');

  test('removes a managed usage description no longer requested', () {
    final patched = patchInfoPlist(before, {
      'camera': 'need camera',
      'location': 'need location',
    }).content;

    final result = pruneInfoPlist(patched, {'camera': 'need camera'});

    expect(result.changed, isTrue);
    expect(result.removed, ['NSLocationWhenInUseUsageDescription']);
    expect(result.content, contains('NSCameraUsageDescription'));
    expect(
      result.content,
      isNot(contains('NSLocationWhenInUseUsageDescription')),
    );
  });

  test('drops the whole managed block once it is emptied', () {
    final patched = patchInfoPlist(before, {'camera': 'need camera'}).content;

    final result = pruneInfoPlist(patched, {});

    expect(result.changed, isTrue);
    expect(result.removed, ['NSCameraUsageDescription']);
    expect(result.content, isNot(contains('flupo:managed')));
    expect(result.content, before);
  });

  test('never touches a key the user added by hand', () {
    final handAdded = before.replaceFirst(
      '</dict>\n</plist>',
      '\t<key>NSMicrophoneUsageDescription</key>\n\t<string>hand-written</string>\n</dict>\n</plist>',
    );
    final patched = patchInfoPlist(handAdded, {
      'camera': 'need camera',
    }).content;

    final result = pruneInfoPlist(patched, {});

    expect(result.removed, ['NSCameraUsageDescription']);
    expect(result.content, contains('NSMicrophoneUsageDescription'));
  });

  test('is a no-op when nothing needs removing', () {
    final patched = patchInfoPlist(before, {'camera': 'need camera'}).content;

    final result = pruneInfoPlist(patched, {'camera': 'need camera'});

    expect(result.changed, isFalse);
    expect(result.content, patched);
  });

  test('is idempotent: pruning twice matches pruning once', () {
    final patched = patchInfoPlist(before, {
      'camera': 'need camera',
      'location': 'need location',
    }).content;

    final first = pruneInfoPlist(patched, {});
    final second = pruneInfoPlist(first.content, {});

    expect(second.changed, isFalse);
    expect(second.content, first.content);
  });
}
