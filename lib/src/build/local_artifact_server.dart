import 'dart:io';

import 'package:file/file.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Serves a single downloaded build artifact over the LAN so a phone can
/// fetch it by scanning a QR code, without needing GitHub credentials
/// device-side.
class LocalArtifactServer {
  LocalArtifactServer._(this._server, this.fileName);

  final HttpServer _server;
  final String fileName;

  int get port => _server.port;

  static Future<LocalArtifactServer> serve(File file, {int port = 0}) async {
    final fileName = file.basename;
    final length = await file.length();

    Future<shelf.Response> handler(shelf.Request request) async {
      if (request.url.path != fileName) {
        return shelf.Response.notFound('Not found');
      }
      return shelf.Response.ok(
        file.openRead(),
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Disposition': 'attachment; filename="$fileName"',
          'Content-Length': '$length',
        },
      );
    }

    final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    return LocalArtifactServer._(server, fileName);
  }

  Uri urlFor(String host) =>
      Uri(scheme: 'http', host: host, port: port, path: fileName);

  Future<void> close() => _server.close(force: true);
}
