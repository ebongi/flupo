import 'dart:convert';

/// What a `flupo start` QR code encodes, and what Flupo Go scans to know
/// where and how to connect its pairing WebSocket.
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

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'projectName': projectName,
    'token': token,
  };

  factory PairingPayload.fromJson(Map<String, dynamic> json) => PairingPayload(
    host: json['host'] as String,
    port: json['port'] as int,
    projectName: json['projectName'] as String,
    token: json['token'] as String,
  );

  String encode() => jsonEncode(toJson());

  factory PairingPayload.decode(String data) =>
      PairingPayload.fromJson(jsonDecode(data) as Map<String, dynamic>);
}
