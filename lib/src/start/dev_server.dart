import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The local WebSocket server `flupo start` runs so the Flupo Go companion
/// app can pair to a dev session and exchange status/reload messages.
///
/// Pairing is single-use: [token] only authenticates the first connection
/// that presents it, so a second device that captured the same QR code (or
/// the same phone reconnecting) can't silently attach mid-session.
class DevServer {
  DevServer._(this._server, this.token);

  final HttpServer _server;
  final String token;

  WebSocketChannel? _client;
  final _reloadController = StreamController<void>.broadcast();
  final _pairedController = StreamController<void>.broadcast();

  int get port => _server.port;

  /// Fires whenever the paired client asks for a reload.
  Stream<void> get onReloadRequested => _reloadController.stream;

  /// Fires once a client presents the correct token and is actually paired —
  /// distinct from the server simply being up and waiting for a connection.
  Stream<void> get onPaired => _pairedController.stream;

  static Future<DevServer> start({int port = 0, String? token}) async {
    final resolvedToken = token ?? const Uuid().v4();
    late final DevServer devServer;

    final handler = webSocketHandler((
      WebSocketChannel channel,
      String? protocol,
    ) {
      devServer._handleConnection(channel);
    });

    final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    devServer = DevServer._(server, resolvedToken);
    return devServer;
  }

  void _handleConnection(WebSocketChannel channel) {
    channel.stream.listen(
      (data) => _handleMessage(channel, data),
      onDone: () {
        if (identical(_client, channel)) _client = null;
      },
    );
  }

  void _handleMessage(WebSocketChannel channel, Object? data) {
    if (!identical(_client, channel)) {
      // Not yet paired: the only valid first message is the pairing token.
      if (data == token && _client == null) {
        _client = channel;
        channel.sink.add(jsonEncode({'type': 'paired'}));
        _pairedController.add(null);
      } else {
        channel.sink.close(4001, 'invalid or already-used pairing token');
      }
      return;
    }

    if (data is! String) return;
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(data) as Map<String, dynamic>;
    } on FormatException {
      return;
    }
    if (decoded['type'] == 'reload') {
      _reloadController.add(null);
    }
  }

  /// Sends a status update to the paired client, if any. Silently a no-op
  /// before pairing or after disconnect — status is best-effort, not
  /// buffered for a client that isn't there yet.
  void broadcastStatus(String message) {
    _client?.sink.add(jsonEncode({'type': 'status', 'message': message}));
  }

  Future<void> close() async {
    await _client?.sink.close();
    await _reloadController.close();
    await _pairedController.close();
    await _server.close(force: true);
  }
}
