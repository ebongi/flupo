import 'package:file/memory.dart';
import 'package:flupo/src/command_runner.dart';
import 'package:flupo/src/manifest/flupo_manifest.dart';
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

  void writeFlutterPubspec({
    String path = '/project/pubspec.yaml',
    String name = 'my_app',
    String version = '1.0.0+1',
  }) {
    fileSystem.file(path)
      ..createSync(recursive: true)
      ..writeAsStringSync('''
name: $name
version: $version
dependencies:
  flutter:
    sdk: flutter
''');
  }

  test('scaffolds flupo.yaml with defaults from pubspec.yaml', () async {
    writeFlutterPubspec();
    fileSystem.currentDirectory = '/project';

    final code = await buildRunner().runFlupo(['init']);

    expect(code, 0);
    final manifestFile = fileSystem.file('/project/flupo.yaml');
    expect(await manifestFile.exists(), isTrue);

    final manifest = await FlupoManifest.fromFile(manifestFile);
    expect(manifest.name, 'my_app');
    expect(manifest.version, '1.0.0+1');
    expect(manifest.identifier, 'com.example.my_app');
    expect(manifest.permissions, isEmpty);
    expect(manifest.build.target, 'apk');
    expect(manifest.build.runner, 'github_actions');
  });

  test('--name and --identifier override pubspec defaults', () async {
    writeFlutterPubspec();
    fileSystem.currentDirectory = '/project';

    final code = await buildRunner().runFlupo([
      'init',
      '--name',
      'override_name',
      '--identifier',
      'com.acme.override',
    ]);

    expect(code, 0);
    final manifest = await FlupoManifest.fromFile(
      fileSystem.file('/project/flupo.yaml'),
    );
    expect(manifest.name, 'override_name');
    expect(manifest.identifier, 'com.acme.override');
  });

  test('--path scaffolds into a different project directory', () async {
    writeFlutterPubspec(path: '/other/pubspec.yaml', name: 'other_app');

    final code = await buildRunner().runFlupo(['init', '--path', '/other']);

    expect(code, 0);
    expect(await fileSystem.file('/other/flupo.yaml').exists(), isTrue);
  });

  test('fails when no pubspec.yaml exists', () async {
    fileSystem.directory('/empty').createSync(recursive: true);
    fileSystem.currentDirectory = '/empty';

    final code = await buildRunner().runFlupo(['init']);

    expect(code, 1);
    expect(logger.errors.single, contains('No pubspec.yaml found'));
  });

  test('fails when pubspec.yaml has no flutter SDK dependency', () async {
    fileSystem.file('/project/pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: not_flutter\nversion: 1.0.0\n');
    fileSystem.currentDirectory = '/project';

    final code = await buildRunner().runFlupo(['init']);

    expect(code, 1);
    expect(
      logger.errors.single,
      contains('does not look like a Flutter project'),
    );
  });

  test('refuses to overwrite an existing flupo.yaml without --force', () async {
    writeFlutterPubspec();
    fileSystem.currentDirectory = '/project';
    fileSystem.file('/project/flupo.yaml')
      ..createSync()
      ..writeAsStringSync('# hand-edited, do not clobber\n');

    final code = await buildRunner().runFlupo(['init']);

    expect(code, 1);
    expect(logger.errors.single, contains('already exists'));
    expect(
      fileSystem.file('/project/flupo.yaml').readAsStringSync(),
      contains('hand-edited'),
    );
  });

  test('--force overwrites an existing flupo.yaml', () async {
    writeFlutterPubspec();
    fileSystem.currentDirectory = '/project';
    fileSystem.file('/project/flupo.yaml')
      ..createSync()
      ..writeAsStringSync('# stale\n');

    final code = await buildRunner().runFlupo(['init', '--force']);

    expect(code, 0);
    expect(
      fileSystem.file('/project/flupo.yaml').readAsStringSync(),
      isNot(contains('stale')),
    );
  });
}
