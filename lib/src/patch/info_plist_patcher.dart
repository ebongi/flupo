import 'package:xml/xml.dart';

import '../manifest/permission_catalog.dart';
import 'patch_sentinels.dart';
import 'permission_patch_result.dart';
import 'permission_prune_result.dart';

String _escapeXmlText(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Inserts any `NS*UsageDescription` key/string pairs [permissions] require
/// but Info.plist doesn't already declare, using the same detect-via-XML,
/// insert-via-text-splice strategy as `patchAndroidManifest` and for the
/// same reason: it leaves existing formatting untouched and is naturally
/// idempotent.
PermissionPatchResult patchInfoPlist(
  String plistContent,
  Map<String, String> permissions,
) {
  final document = XmlDocument.parse(plistContent);
  final rootDict = document.rootElement.getElement('dict');
  if (rootDict == null) {
    throw const FormatException('Info.plist has no root <dict> element.');
  }

  final existingKeys = rootDict
      .findElements('key')
      .map((e) => e.innerText)
      .toSet();

  final missing = <String, String>{
    for (final entry in permissions.entries)
      if (!existingKeys.contains(
        permissionCatalog[entry.key]!.iosUsageDescriptionKey,
      ))
        permissionCatalog[entry.key]!.iosUsageDescriptionKey: entry.value,
  };

  if (missing.isEmpty) {
    return PermissionPatchResult(
      content: plistContent,
      changed: false,
      added: const [],
    );
  }

  final block = StringBuffer()..writeln('\t$managedSentinelStart');
  missing.forEach((key, description) {
    block
      ..writeln('\t<key>$key</key>')
      ..writeln('\t<string>${_escapeXmlText(description)}</string>');
  });
  block.write('\t$managedSentinelEnd\n');

  final closingTagIndex = plistContent.lastIndexOf('</dict>');
  if (closingTagIndex == -1) {
    throw const FormatException('Info.plist has no closing </dict> tag.');
  }

  final newContent =
      plistContent.substring(0, closingTagIndex) +
      block.toString() +
      plistContent.substring(closingTagIndex);

  return PermissionPatchResult(
    content: newContent,
    changed: true,
    added: missing.keys.toList(),
  );
}

final RegExp _plistKeyValuePattern = RegExp(
  r'<key>([^<]+)</key>\s*\n\s*<string>([^<]*)</string>',
);

/// Removes `NS*UsageDescription` key/string pairs inside `flupo:managed`
/// blocks that [permissions] no longer requests. Never touches anything
/// outside those blocks. A block emptied entirely by pruning is dropped
/// along with its sentinels.
PermissionPruneResult pruneInfoPlist(
  String plistContent,
  Map<String, String> permissions,
) {
  final requestedKeys = <String>{
    for (final key in permissions.keys)
      permissionCatalog[key]!.iosUsageDescriptionKey,
  };

  final removed = <String>[];
  final newContent = plistContent.replaceAllMapped(managedBlockPattern, (
    match,
  ) {
    final indent = match.group(1)!;
    final inner = match.group(2)!;
    final entries = _plistKeyValuePattern
        .allMatches(inner)
        .map((m) => MapEntry(m.group(1)!, m.group(2)!))
        .toList();
    final kept = entries.where((e) => requestedKeys.contains(e.key)).toList();
    final droppedHere = entries
        .where((e) => !requestedKeys.contains(e.key))
        .map((e) => e.key)
        .toList();

    if (droppedHere.isEmpty) return match.group(0)!;
    removed.addAll(droppedHere);
    if (kept.isEmpty) return '';

    final block = StringBuffer()..writeln('$indent$managedSentinelStart');
    for (final entry in kept) {
      block
        ..writeln('$indent<key>${entry.key}</key>')
        ..writeln('$indent<string>${entry.value}</string>');
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
