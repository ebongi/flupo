import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:process/process.dart';

class DaemonEvent {
  const DaemonEvent(this.name, this.params);

  final String name;
  final Map<String, dynamic> params;
}

/// Parses one line of `flutter run --machine`'s stdout as a daemon event.
///
/// The real protocol is internal/undocumented and not identical across
/// Flutter versions, but every version emits unsolicited events as a
/// single-element JSON array `[{"event": "...", "params": {...}}]` — that
/// shape is what this reads. Non-event lines (responses to requests we
/// didn't send, or malformed/partial output) are simply ignored.
DaemonEvent? parseDaemonEvent(String line) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) return null;

  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
  if (decoded is! List || decoded.isEmpty) return null;

  final message = decoded.first;
  if (message is! Map || !message.containsKey('event')) return null;

  final params =
      (message['params'] as Map?)?.cast<String, dynamic>() ?? const {};
  return DaemonEvent(message['event'] as String, params);
}

/// A pragmatic, intentionally partial client for Flutter's internal
/// `--machine` daemon protocol — just enough to detect app start, trigger a
/// reload/restart, and stop cleanly. This is `flupo start`'s actual reload
/// mechanism for its MVP: real bytecode streaming to a custom client is a
/// separate, much larger effort tracked as a later phase.
class FlutterDaemonProxy {
  FlutterDaemonProxy._(this._process, this.events);

  final Process _process;
  final Stream<DaemonEvent> events;
  String? appId;

  static Future<FlutterDaemonProxy> start(
    ProcessManager processManager, {
    required String projectDirectory,
    String? deviceId,
  }) async {
    final process = await processManager.start([
      'flutter',
      'run',
      '--machine',
      if (deviceId != null) ...['-d', deviceId],
    ], workingDirectory: projectDirectory);

    final controller = StreamController<DaemonEvent>.broadcast();
    final proxy = FlutterDaemonProxy._(process, controller.stream);

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final event = parseDaemonEvent(line);
          if (event == null) return;
          if (event.name == 'app.start') {
            proxy.appId = event.params['appId'] as String?;
          }
          controller.add(event);
        });

    return proxy;
  }

  void triggerReload({bool fullRestart = false}) {
    final id = appId;
    if (id == null) return;
    _send('app.restart', {'appId': id, 'fullRestart': fullRestart});
  }

  void stop() {
    final id = appId;
    if (id != null) {
      _send('app.stop', {'appId': id});
    }
    _process.kill();
  }

  void _send(String method, Map<String, dynamic> params) {
    _process.stdin.writeln(
      jsonEncode([
        {'id': 0, 'method': method, 'params': params},
      ]),
    );
  }
}
