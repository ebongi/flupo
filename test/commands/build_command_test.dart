import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:args/command_runner.dart';
import 'package:file/memory.dart';
import 'package:flupo/src/build/github_credentials_store.dart';
import 'package:flupo/src/command_runner.dart';
import 'package:flupo/src/commands/build_command.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../support/mocks.dart';
import '../support/recording_logger.dart';

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');
ProcessResult _fail(String stderr) => ProcessResult(0, 1, '', stderr);

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

  void writeManifest({String extra = ''}) {
    fileSystem.file('/project/flupo.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
name: my_app
version: 1.0.0+1
identifier: com.acme.myapp
build:
  target: apk
  runner: github_actions
$extra
''');
  }

  void stubCleanPushedGit() {
    when(
      () => processManager.run(
        any(),
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((invocation) async {
      final args = (invocation.positionalArguments.first as List<Object?>)
          .cast<String>()
          .skip(1)
          .toList();
      if (args.join(' ') == 'rev-parse --abbrev-ref HEAD') return _ok('main\n');
      if (args.join(' ') == 'rev-parse HEAD') return _ok('deadbeefcafe\n');
      if (args.join(' ') == 'status --porcelain') return _ok('');
      if (args.join(' ') == 'rev-parse --abbrev-ref @{u}') {
        return _ok('origin/main\n');
      }
      if (args.join(' ') == 'rev-list @{u}..HEAD --count') return _ok('0\n');
      throw UnsupportedError('Unexpected git command: $args');
    });
  }

  void stubDirtyGit() {
    when(
      () => processManager.run(
        any(),
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((invocation) async {
      final args = (invocation.positionalArguments.first as List<Object?>)
          .cast<String>()
          .skip(1)
          .toList();
      if (args.join(' ') == 'rev-parse --abbrev-ref HEAD') return _ok('main\n');
      if (args.join(' ') == 'rev-parse HEAD') return _ok('deadbeefcafe\n');
      if (args.join(' ') == 'status --porcelain') {
        return _ok(' M lib/main.dart\n');
      }
      if (args.join(' ') == 'rev-parse --abbrev-ref @{u}') {
        return _fail('no upstream');
      }
      throw UnsupportedError('Unexpected git command: $args');
    });
  }

  List<int> buildFakeApkZip() {
    final archive = Archive();
    final bytes = utf8.encode('fake apk bytes');
    archive.addFile(ArchiveFile('app-release.apk', bytes.length, bytes));
    return ZipEncoder().encode(archive);
  }

  http.Client buildMockGithub({
    required List<int> zipBytes,
    String conclusion = 'success',
  }) {
    String? correlationId;
    return MockClient((request) async {
      if (request.method == 'POST' &&
          request.url.path.contains('/dispatches')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        correlationId = (body['inputs'] as Map)['correlation_id'] as String;
        return http.Response('', 204);
      }
      if (request.method == 'GET' && request.url.path.endsWith('/runs')) {
        return http.Response(
          jsonEncode({
            'workflow_runs': [
              {
                'id': 1,
                'name': 'flupo $correlationId',
                'status': 'completed',
                'conclusion': conclusion,
                'html_url': 'https://github.com/acme/app/actions/runs/1',
              },
            ],
          }),
          200,
        );
      }
      if (request.method == 'GET' && request.url.path.endsWith('/artifacts')) {
        return http.Response(
          jsonEncode({
            'artifacts': [
              {
                'id': 5,
                'name': 'app-release',
                'archive_download_url': 'https://api.github.com/download/5',
              },
            ],
          }),
          200,
        );
      }
      if (request.method == 'GET' &&
          request.url.path.endsWith('/actions/runs/1')) {
        return http.Response(
          jsonEncode({
            'id': 1,
            'name': 'flupo $correlationId',
            'status': 'completed',
            'conclusion': conclusion,
            'html_url': 'https://github.com/acme/app/actions/runs/1',
          }),
          200,
        );
      }
      if (request.url.toString() == 'https://api.github.com/download/5') {
        return http.Response(
          '',
          302,
          headers: {'location': 'https://blob.example/artifact.zip'},
        );
      }
      if (request.url.toString() == 'https://blob.example/artifact.zip') {
        return http.Response.bytes(zipBytes, 200);
      }
      return http.Response('unexpected: ${request.method} ${request.url}', 500);
    });
  }

  test('fails cleanly when flupo.yaml is missing', () async {
    final runner = FlupoCommandRunner(
      fileSystem: fileSystem,
      processManager: processManager,
      logger: logger,
    );

    final code = await runner.runFlupo(['build']);

    expect(code, 1);
    expect(logger.errors.single, contains('Run `flupo init` first'));
  });

  test('fails when repo/workflow are not configured anywhere', () async {
    writeManifest();
    final runner = FlupoCommandRunner(
      fileSystem: fileSystem,
      processManager: processManager,
      logger: logger,
    );

    final code = await runner.runFlupo(['build']);

    expect(code, 1);
    expect(logger.errors.single, contains('Missing GitHub target'));
  });

  test('fails when no GitHub token is available', () async {
    writeManifest(
      extra: '''
  github:
    repo: acme/app
    workflow: build.yml
''',
    );
    // Deliberately empty (never falls back to the real environment or disk)
    // so this can't pass or fail depending on the machine it runs on.
    final buildCommand = BuildCommand(
      fileSystem: fileSystem,
      processManager: processManager,
      logger: logger,
      httpClient: MockClient((request) async {
        fail('GitHub API should not be contacted without a token');
      }),
      credentialsStore: const CompositeGithubCredentialsStore([]),
    );
    final runner = CommandRunner<int>('flupo', 'test runner')
      ..addCommand(buildCommand);

    final code = await runner.run(['build']) ?? 0;

    expect(code, 1);
    expect(logger.errors.single, contains('No GitHub token found'));
  });

  group('with credentials and git wired up', () {
    Future<int> runBuild(
      http.Client httpClient, {
      List<String> extraArgs = const [],
    }) async {
      final buildCommand = BuildCommand(
        fileSystem: fileSystem,
        processManager: processManager,
        logger: logger,
        httpClient: httpClient,
        credentialsStore: EnvGithubCredentialsStore({
          'FLUPO_GITHUB_TOKEN': 'test-token',
        }),
        serveDuration: Duration.zero,
        // Must never emit or close: `.first` on a stream that closes without
        // an element throws immediately, which would race (and sometimes
        // beat) the zero-duration timeout below.
        interruptSignal: StreamController<ProcessSignal>().stream,
      );
      final runner = CommandRunner<int>('flupo', 'test runner')
        ..addCommand(buildCommand);
      final result = await runner.run(['build', ...extraArgs]);
      return result ?? 0;
    }

    test(
      'fails on a dirty working tree unless --allow-dirty is passed',
      () async {
        writeManifest(
          extra: '''
  github:
    repo: acme/app
    workflow: build.yml
''',
        );
        stubDirtyGit();

        final code = await runBuild(
          MockClient((request) async {
            fail('GitHub API should not be contacted when the tree is dirty');
          }),
        );

        expect(code, 1);
        expect(logger.errors.single, contains('uncommitted changes'));
      },
    );

    test(
      'happy path: dispatches, watches, downloads, and saves the artifact',
      () async {
        writeManifest(
          extra: '''
  github:
    repo: acme/app
    workflow: build.yml
''',
        );
        stubCleanPushedGit();
        final zipBytes = buildFakeApkZip();

        final code = await runBuild(buildMockGithub(zipBytes: zipBytes));

        expect(code, 0);
        expect(
          fileSystem.file('/project/app-release.apk').existsSync(),
          isTrue,
        );
        expect(
          fileSystem.file('/project/app-release.apk').readAsStringSync(),
          'fake apk bytes',
        );
      },
    );

    test('fails when the GitHub Actions run does not succeed', () async {
      writeManifest(
        extra: '''
  github:
    repo: acme/app
    workflow: build.yml
''',
      );
      stubCleanPushedGit();
      final zipBytes = buildFakeApkZip();

      final code = await runBuild(
        buildMockGithub(zipBytes: zipBytes, conclusion: 'failure'),
      );

      expect(code, 1);
      expect(logger.errors.single, contains('did not succeed'));
    });

    test('--allow-dirty proceeds despite a dirty working tree', () async {
      writeManifest(
        extra: '''
  github:
    repo: acme/app
    workflow: build.yml
''',
      );
      stubDirtyGit();
      final zipBytes = buildFakeApkZip();

      final code = await runBuild(
        buildMockGithub(zipBytes: zipBytes),
        extraArgs: ['--allow-dirty'],
      );

      expect(code, 0);
    });
  });
}
