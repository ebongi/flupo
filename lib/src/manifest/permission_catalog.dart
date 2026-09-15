/// Maps a `flupo.yaml` permission key to the platform-specific declarations
/// `flupo patch` must inject to grant it.
class PermissionSpec {
  const PermissionSpec({
    required this.androidPermissions,
    required this.iosUsageDescriptionKey,
  });

  /// One or more `android.permission.*` strings this key maps to.
  final List<String> androidPermissions;

  /// The `Info.plist` key (e.g. `NSCameraUsageDescription`) whose value is
  /// the permission's user-facing description string from `flupo.yaml`.
  final String iosUsageDescriptionKey;
}

const Map<String, PermissionSpec> permissionCatalog = {
  'camera': PermissionSpec(
    androidPermissions: ['android.permission.CAMERA'],
    iosUsageDescriptionKey: 'NSCameraUsageDescription',
  ),
  'location': PermissionSpec(
    androidPermissions: [
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.ACCESS_COARSE_LOCATION',
    ],
    iosUsageDescriptionKey: 'NSLocationWhenInUseUsageDescription',
  ),
  'microphone': PermissionSpec(
    androidPermissions: ['android.permission.RECORD_AUDIO'],
    iosUsageDescriptionKey: 'NSMicrophoneUsageDescription',
  ),
  'photos': PermissionSpec(
    androidPermissions: ['android.permission.READ_MEDIA_IMAGES'],
    iosUsageDescriptionKey: 'NSPhotoLibraryUsageDescription',
  ),
  'contacts': PermissionSpec(
    androidPermissions: ['android.permission.READ_CONTACTS'],
    iosUsageDescriptionKey: 'NSContactsUsageDescription',
  ),
  'bluetooth': PermissionSpec(
    androidPermissions: [
      'android.permission.BLUETOOTH_SCAN',
      'android.permission.BLUETOOTH_CONNECT',
    ],
    iosUsageDescriptionKey: 'NSBluetoothAlwaysUsageDescription',
  ),
};
