import 'package:xml/xml.dart';

import '../manifest/permission_catalog.dart';
import 'patch_sentinels.dart';
import 'permission_patch_result.dart';
import 'permission_prune_result.dart';

/// Inserts any `<uses-permission>` elements [permissions] (flupo.yaml
/// permission keys) require but the manifest doesn't already declare.
///
/// Detection parses the XML (so it's correct regardless of formatting), but
/// insertion splices raw text right before `</manifest>` rather than
/// re-serializing the whole document — this leaves everything the user
/// already wrote byte-for-byte untouched, which both keeps diffs minimal and
/// makes a true no-op run naturally idempotent (identical input in, identical
/// output out).
PermissionPatchResult patchAndroidManifest(
  String xmlContent,
  Map<String, String> permissions,
) {
  final requested = <String>{
    for (final key in permissions.keys)
      ...permissionCatalog[key]!.androidPermissions,
  };

  final document = XmlDocument.parse(xmlContent);
  final existing = document.rootElement
      .findElements('uses-permission')
      .map((element) => element.getAttribute('android:name'))
      .whereType<String>()
      .toSet();

  final missing = requested.difference(existing).toList()..sort();
  if (missing.isEmpty) {
    return PermissionPatchResult(
      content: xmlContent,
      changed: false,
      added: const [],
    );
  }

  final block = StringBuffer()..writeln('    $managedSentinelStart');
  for (final name in missing) {
    block.writeln('    <uses-permission android:name="$name"/>');
  }
  block.write('    $managedSentinelEnd\n');

  final closingTagIndex = xmlContent.lastIndexOf('</manifest>');
  if (closingTagIndex == -1) {
    throw const FormatException(
      'AndroidManifest.xml has no closing </manifest> tag.',
    );
  }

  final newContent =
      xmlContent.substring(0, closingTagIndex) +
      block.toString() +
      xmlContent.substring(closingTagIndex);

  return PermissionPatchResult(
    content: newContent,
    changed: true,
    added: missing,
  );
}

final RegExp _androidPermissionNamePattern = RegExp(r'android:name="([^"]+)"');

/// Removes `<uses-permission>` entries inside `flupo:managed` blocks that
/// [permissions] no longer requests. Never touches anything outside those
/// blocks — a permission the user added by hand is never flupo's to remove.
/// A block emptied entirely by pruning is dropped along with its sentinels.
PermissionPruneResult pruneAndroidManifest(
  String xmlContent,
  Map<String, String> permissions,
) {
  final requested = <String>{
    for (final key in permissions.keys)
      ...permissionCatalog[key]!.androidPermissions,
  };

  final removed = <String>[];
  final newContent = xmlContent.replaceAllMapped(managedBlockPattern, (match) {
    final indent = match.group(1)!;
    final inner = match.group(2)!;
    final names = _androidPermissionNamePattern
        .allMatches(inner)
        .map((m) => m.group(1)!)
        .toList();
    final kept = names.where(requested.contains).toList();
    final droppedHere = names.where((n) => !requested.contains(n)).toList();

    if (droppedHere.isEmpty) return match.group(0)!;
    removed.addAll(droppedHere);
    if (kept.isEmpty) return '';

    final block = StringBuffer()..writeln('$indent$managedSentinelStart');
    for (final name in kept) {
      block.writeln('$indent<uses-permission android:name="$name"/>');
    }
    block.write('$indent$managedSentinelEnd\n');
    return block.toString();
  });

  return PermissionPruneResult(
    content: newContent,
    changed: removed.isNotEmpty,
    removed: removed,
  );
}
