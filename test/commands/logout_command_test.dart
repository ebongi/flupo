import 'package:file/memory.dart';
import 'package:flupo/src/build/github_credentials_store.dart';
import 'package:flupo/src/command_runner.dart';
import 'package:test/test.dart';

import '../support/mocks.dart';
import '../support/recording_logger.dart';

void main() {
  late MemoryFileSystem fileSystem;
  late RecordingLogger logger;

  setUp(() {
    fileSystem = MemoryFileSystem();
    logger = RecordingLogger();
  });

  FlupoCommandRunner buildRunner() => FlupoCommandRunner(
    fileSystem: fileSystem,
    processManager: MockProcessManager(),
    logger: logger,
  );

  test('removes previously stored credentials', () async {
    final store = FileGithubCredentialsStore(
      defaultGithubCredentialsFile(fileSystem),
    );
    await store.write('abc123');

    final code = await buildRunner().runFlupo(['logout']);

    expect(code, 0);
    expect(await store.read(), isNull);
    expect(logger.infos, anyElement(contains('Removed')));
  });

  test('is a no-op when nothing was stored', () async {
    final code = await buildRunner().runFlupo(['logout']);

    expect(code, 0);
    expect(logger.infos, anyElement(contains('Not logged in')));
  });
}
