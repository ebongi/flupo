import 'package:flupo/src/start/flutter_daemon_proxy.dart';
import 'package:test/test.dart';

void main() {
  group('parseDaemonEvent', () {
    test('parses a well-formed event line', () {
      final event = parseDaemonEvent(
        '[{"event":"app.start","params":{"appId":"abc123"}}]',
      );

      expect(event, isNotNull);
      expect(event!.name, 'app.start');
      expect(event.params['appId'], 'abc123');
    });

    test('defaults params to an empty map when absent', () {
      final event = parseDaemonEvent('[{"event":"daemon.connected"}]');

      expect(event!.name, 'daemon.connected');
      expect(event.params, isEmpty);
    });

    test('ignores non-JSON lines', () {
      expect(parseDaemonEvent('Launching lib/main.dart on Pixel...'), isNull);
    });

    test('ignores JSON that is not a single-element event array', () {
      expect(parseDaemonEvent('[]'), isNull);
      expect(parseDaemonEvent('[{"id":0,"result":{}}]'), isNull);
      expect(parseDaemonEvent('{"event":"app.start"}'), isNull);
    });

    test('tolerates surrounding whitespace', () {
      expect(parseDaemonEvent('  [{"event":"app.stop"}]  \n'), isNotNull);
    });
  });
}
