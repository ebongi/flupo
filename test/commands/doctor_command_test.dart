import 'dart:convert';
import 'dart:io';

import 'package:file/memory.dart';
import 'package:flupo/src/command_runner.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../support/mocks.dart';
import '../support/recording_logger.dart';

ProcessResult _resultFor(List<Object?> command, {required bool adbMissing}) {
  switch (command.first) {
    case 'git':
      return ProcessResult(0, 0, 'git version 2.43.0', '');
    case 'dart':
      return ProcessResult(0, 0, 'Dart SDK version: 3.12.2 (stable)', '');
    case 'flutter':
      return ProcessResult(
        0,
        0,
        jsonEncode({'frameworkVersion': '3.44.9', 'channel': 'stable'}),
        '',
      );
    case 'adb':
      if (adbMissing) throw const ProcessException('adb', ['version']);
      return ProcessResult(0, 0, 'Android Debug Bridge version 1.0.41', '');
    default:
      throw UnsupportedError('Unexpected command: $command');
  }
}

void main() {
  late MockProcessManager processManager;
  late RecordingLogger logger;

  setUp(() {
    processManager = MockProcessManager();
    logger = RecordingLogger();
  });

  void stubAllTools({bool adbMissing = false}) {
    when(() => processManager.run(any())).thenAnswer((invocation) async {
      final command = invocation.positionalArguments.first as List<Object?>;
      return _resultFor(command, adbMissing: adbMissing);
    });
  }

  FlupoCommandRunner buildRunner() => FlupoCommandRunner(
    fileSystem: MemoryFileSystem(),
    processManager: processManager,
    logger: logger,
  );

  test('exits 0 when all tools, including adb, are present', () async {
    stubAllTools();

    final code = await buildRunner().runFlupo(['doctor']);

    expect(code, 0);
  });

  test('exits 0 when only adb is missing, since it is optional', () async {
    stubAllTools(adbMissing: true);

    final code = await buildRunner().runFlupo(['doctor']);

    expect(code, 0);
    expect(logger.infos, hasLength(4));
    expect(logger.infos, anyElement(contains('[WARN]')));
  });

  test('exits non-zero when a required tool is missing', () async {
    when(() => processManager.run(any())).thenAnswer((invocation) async {
      final command = invocation.positionalArguments.first as List<Object?>;
      if (command.first == 'git') {
        throw const ProcessException('git', ['--version']);
      }
      return _resultFor(command, adbMissing: false);
    });

    final code = await buildRunner().runFlupo(['doctor']);

    expect(code, 1);
    expect(logger.infos, hasLength(4));
    expect(logger.infos, anyElement(contains('[MISSING]')));
  });

  test('--json prints machine-readable output for all four tools', () async {
    stubAllTools();

    final code = await buildRunner().runFlupo(['doctor', '--json']);

    expect(code, 0);
    expect(logger.infos, hasLength(1));
    final decoded = jsonDecode(logger.infos.single) as Map<String, dynamic>;
    expect(
      decoded.keys,
      containsAll(['Git', 'Dart SDK', 'Flutter SDK', 'ADB']),
    );
    expect(decoded['Git']['status'], 'ok');
    expect(decoded['ADB']['required'], false);
  });
}
