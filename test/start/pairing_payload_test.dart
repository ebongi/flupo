import 'package:flupo/src/start/pairing_payload.dart';
import 'package:test/test.dart';

void main() {
  test('round-trips through encode/decode', () {
    const payload = PairingPayload(
      host: '192.168.1.23',
      port: 4567,
      projectName: 'flupo_go',
      token: 'abc-123',
    );

    final decoded = PairingPayload.decode(payload.encode());

    expect(decoded.host, payload.host);
    expect(decoded.port, payload.port);
    expect(decoded.projectName, payload.projectName);
    expect(decoded.token, payload.token);
  });
}
