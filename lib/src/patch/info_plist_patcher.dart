import 'package:xml/xml.dart';

import '../manifest/permission_catalog.dart';
import 'patch_sentinels.dart';
import 'permission_patch_result.dart';

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
