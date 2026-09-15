import 'dart:convert';

/// What `flupo start`'s QR code encodes. Mirrors the CLI's
/// `lib/src/start/pairing_payload.dart` — duplicated rather than shared,
/// since flupo and flupo_go are intentionally independent packages.
class PairingPayload {
  const PairingPayload({
    required this.host,
    required this.port,
    required this.projectName,
    required this.token,
  });

  final String host;
  final int port;
  final String projectName;
  final String token;

  Uri get wsUri => Uri(scheme: 'ws', host: host, port: port);

  factory PairingPayload.decode(String data) {
    final json = jsonDecode(data) as Map<String, dynamic>;
    return PairingPayload(
      host: json['host'] as String,
      port: json['port'] as int,
      projectName: json['projectName'] as String,
      token: json['token'] as String,
    );
  }
}
