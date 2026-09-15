import 'dart:io';

/// Best-effort LAN IPv4 address detection, for QR codes a phone on the same
/// Wi-Fi can actually reach. Falls back to `null` (callers should use
/// 'localhost') rather than throwing — this is a nice-to-have, not something
/// that should fail a command over.
Future<String?> detectLocalIp() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) return address.address;
      }
    }
  } catch (_) {
    // Ignore and fall back to localhost.
  }
  return null;
}
