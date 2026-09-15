import 'dart:convert';

import 'package:flupo/src/start/dev_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  late DevServer server;

  setUp(() async {
    server = await DevServer.start(token: 'correct-token');
  });

  tearDown(() => server.close());

  WebSocketChannel connect() =>
      WebSocketChannel.connect(Uri.parse('ws://localhost:${server.port}'));

  test('accepts the correct pairing token and fires onPaired', () async {
    final pairedFuture = server.onPaired.first;
    final client = connect();
    await client.ready;
    client.sink.add('correct-token');

    final response =
        jsonDecode(await client.stream.first as String) as Map<String, dynamic>;

    expect(response['type'], 'paired');
    await pairedFuture.timeout(const Duration(seconds: 5));
    await client.sink.close();
  });

  test('does not fire onPaired when no client has connected', () async {
    var paired = false;
    final sub = server.onPaired.listen((_) => paired = true);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(paired, isFalse);
    await sub.cancel();
  });

  test('rejects an incorrect pairing token', () async {
    final client = connect();
    await client.ready;
    client.sink.add('wrong-token');

    await client.stream.isEmpty.then((_) {});
    expect(client.closeCode, 4001);
  });

  test(
    'is single-use: a second connection cannot pair after the first does',
    () async {
      final first = connect();
      await first.ready;
      first.sink.add('correct-token');
      await first.stream.first; // wait for the "paired" ack

      final second = connect();
      await second.ready;
      second.sink.add('correct-token');
      await second.stream.isEmpty.then((_) {});

      expect(second.closeCode, 4001);
      await first.sink.close();
    },
  );

  test('broadcasts status only to the paired client', () async {
    final client = connect();
    await client.ready;
    final stream = client.stream.asBroadcastStream();
    client.sink.add('correct-token');
    await stream.first; // "paired" ack

    server.broadcastStatus('app.start');
    final message =
        jsonDecode(await stream.first as String) as Map<String, dynamic>;

    expect(message['type'], 'status');
    expect(message['message'], 'app.start');
    await client.sink.close();
  });

  test(
    'a "reload" message from the paired client fires onReloadRequested',
    () async {
      final client = connect();
      await client.ready;
      client.sink.add('correct-token');
      await client.stream.first; // "paired" ack

      final reloadFuture = server.onReloadRequested.first;
      client.sink.add(jsonEncode({'type': 'reload'}));

      await reloadFuture.timeout(const Duration(seconds: 5));
      await client.sink.close();
    },
  );
}
