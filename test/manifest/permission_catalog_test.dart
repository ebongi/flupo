import 'package:flupo/src/manifest/permission_catalog.dart';
import 'package:test/test.dart';

void main() {
  test(
    'every catalog entry has at least one Android permission and an iOS key',
    () {
      expect(permissionCatalog, isNotEmpty);
      for (final entry in permissionCatalog.entries) {
        expect(entry.value.androidPermissions, isNotEmpty, reason: entry.key);
        expect(
          entry.value.iosUsageDescriptionKey,
          isNotEmpty,
          reason: entry.key,
        );
      }
    },
  );
}
