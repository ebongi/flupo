import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:process/process.dart';

import '../manifest/flupo_manifest.dart';
import '../start/dev_server.dart';
import '../start/flutter_daemon_proxy.dart';
import '../start/pairing_payload.dart';
import '../util/local_ip.dart';
import '../util/logger.dart';
import '../util/terminal_qr.dart';

class StartCommand extends Command<int> {
  StartCommand({
    required this.fileSystem,
    required this.processManager,
    required this.logger,
    Stream<ProcessSignal>? interruptSignal,
  }) : interruptSignal = interruptSignal ?? ProcessSignal.sigint.watch() {
    argParser
      ..addOption(
        'path',
        help:
            'The Flutter project root to run (defaults to the current '
            'directory).',
      )
      ..addOption(
        'device-id',
        abbr: 'd',
        help:
            'Target device id, as shown by `flutter devices` (passed to '
            '`flutter run -d`).',
      );
  }

  final FileSystem fileSystem;
  final ProcessManager processManager;
  final Logger logger;
  final Stream<ProcessSignal> interruptSignal;

  @override
  String get name => 'start';

  @override
  String get description =>
      'Runs your app locally and pairs the Flupo Go companion app for '
      'status updates and phone-triggered reload.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final rawPath = results.option('path');
    final projectDir = rawPath == null
        ? fileSystem.currentDirectory
        : fileSystem.directory(
            fileSystem.path.normalize(fileSystem.path.absolute(rawPath)),
          );

    final FlupoManifest manifest;
    try {
      manifest = await FlupoManifest.fromFile(
        projectDir.childFile('flupo.yaml'),
      );
    } on ManifestValidationException catch (e) {
      logger.error(e.toString());
      return 1;
    }

    final devicesResult = await processManager.run([
      'flutter',
      'devices',
      '--machine',
    ]);
    if (devicesResult.exitCode != 0) {
      logger.error('Could not list Flutter devices: ${devicesResult.stderr}');
      return 1;
    }
    final List<dynamic> devices;
    try {
      devices = jsonDecode(devicesResult.stdout.toString()) as List<dynamic>;
    } on FormatException {
      logger.error('Could not parse `flutter devices --machine` output.');
      return 1;
    }
    if (devices.isEmpty) {
      logger.error(
        'No connected devices found. Connect a device or start an emulator, '
        'then try again.',
      );
      return 1;
    }

    final devServer = await DevServer.start();
    final daemon = await FlutterDaemonProxy.start(
      processManager,
      projectDirectory: projectDir.path,
      deviceId: results.option('device-id'),
    );

    final payload = PairingPayload(
      host: await detectLocalIp() ?? 'localhost',
      port: devServer.port,
      projectName: manifest.name,
      token: devServer.token,
    );
    logger.info('Scan this QR with Flupo Go to pair:');
    logger.info(renderTerminalQr(payload.encode()));

    final daemonSub = daemon.events.listen((event) {
      devServer.broadcastStatus(event.name);
      logger.info('[flutter] ${event.name}');
    });
    final reloadSub = devServer.onReloadRequested.listen((_) {
      logger.info('Reload requested from Flupo Go.');
      daemon.triggerReload();
    });

    logger.info(
      'Paired and watching for reload requests — press Ctrl+C to stop.',
    );
    await interruptSignal.first;

    await reloadSub.cancel();
    await daemonSub.cancel();
    daemon.stop();
    await devServer.close();

    return 0;
  }
}
