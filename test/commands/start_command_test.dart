import 'dart:io';

import 'package:file/memory.dart';
import 'package:flupo/src/command_runner.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../support/mocks.dart';
import '../support/recording_logger.dart';

void main() {
  late MemoryFileSystem fileSystem;
  late RecordingLogger logger;
  late MockProcessManager processManager;

  setUp(() {
    fileSystem = MemoryFileSystem();
    logger = RecordingLogger();
    processManager = MockProcessManager();
    fileSystem.directory('/project').createSync(recursive: true);
    fileSystem.currentDirectory = '/project';
  });

  void writeManifest() {
    fileSystem.file('/project/flupo.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
name: my_app
version: 1.0.0+1
identifier: com.acme.myapp
''');
  }

  FlupoCommandRunner buildRunner() => FlupoCommandRunner(
    fileSystem: fileSystem,
    processManager: processManager,
    logger: logger,
  );

  test('fails cleanly when flupo.yaml is missing', () async {
    final code = await buildRunner().runFlupo(['start']);

    expect(code, 1);
    expect(logger.errors.single, contains('Run `flupo init` first'));
  });

  test('fails when `flutter devices --machine` exits non-zero', () async {
    writeManifest();
    when(() => processManager.run(any())).thenAnswer(
      (_) async => ProcessResult(0, 1, '', 'no flutter SDK on PATH'),
    );

    final code = await buildRunner().runFlupo(['start']);

    expect(code, 1);
    expect(logger.errors.single, contains('Could not list Flutter devices'));
  });

  test('fails cleanly when no devices are connected', () async {
    writeManifest();
    when(
      () => processManager.run(any()),
    ).thenAnswer((_) async => ProcessResult(0, 0, '[]', ''));

    final code = await buildRunner().runFlupo(['start']);

    expect(code, 1);
    expect(logger.errors.single, contains('No connected devices found'));
  });

  test('fails cleanly when device output is not valid JSON', () async {
    writeManifest();
    when(
      () => processManager.run(any()),
    ).thenAnswer((_) async => ProcessResult(0, 0, 'not json', ''));

    final code = await buildRunner().runFlupo(['start']);

    expect(code, 1);
    expect(logger.errors.single, contains('Could not parse'));
  });
}
