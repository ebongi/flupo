import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:file/memory.dart';
import 'package:flupo/src/build/github_credentials_store.dart';
import 'package:flupo/src/commands/login_command.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  });

  Future<int> runLogin(
    List<String> args, {
    required http.Client httpClient,
    String? Function()? readToken,
    Map<String, String> environment = const {},
  }) async {
    final command = LoginCommand(
      fileSystem: fileSystem,
      processManager: processManager,
      logger: logger,
      httpClient: httpClient,
      readToken: readToken,
      environment: environment,
    );
    final runner = CommandRunner<int>('flupo', 'test runner')
      ..addCommand(command);
    return await runner.run(['login', ...args]) ?? 0;
  }

  http.Client mockGithubUser({
    int statusCode = 200,
    String login = 'ebongi',
    String? scopesHeader = 'repo, workflow',
  }) => MockClient((request) async {
    return http.Response(
      jsonEncode({'login': login}),
      statusCode,
      headers: {'x-oauth-scopes': ?scopesHeader},
    );
  });

  test('--token validates, stores, and reports who you are', () async {
    final code = await runLogin([
      '--token',
      'abc123',
    ], httpClient: mockGithubUser());

    expect(code, 0);
    expect(logger.infos, anyElement(contains('ebongi')));

    final store = FileGithubCredentialsStore(
      defaultGithubCredentialsFile(fileSystem),
    );
    expect(await store.read(), 'abc123');
  });

  test('warns but still stores a token missing the workflow scope', () async {
    final code = await runLogin([
      '--token',
      'abc123',
    ], httpClient: mockGithubUser(scopesHeader: 'repo'));

    expect(code, 0);
    expect(logger.warnings, anyElement(contains('workflow')));

    final store = FileGithubCredentialsStore(
      defaultGithubCredentialsFile(fileSystem),
    );
    expect(await store.read(), 'abc123');
  });

  test('rejects an invalid token and stores nothing', () async {
    final code = await runLogin([
      '--token',
      'bad-token',
    ], httpClient: mockGithubUser(statusCode: 401));

    expect(code, 1);
    expect(logger.errors, anyElement(contains('rejected')));

    final store = FileGithubCredentialsStore(
      defaultGithubCredentialsFile(fileSystem),
    );
    expect(await store.read(), isNull);
  });

  test(
    'falls back to the interactive prompt when --token is omitted',
    () async {
      final code = await runLogin(
        [],
        httpClient: mockGithubUser(),
        readToken: () => 'from-prompt',
      );

      expect(code, 0);
      final store = FileGithubCredentialsStore(
        defaultGithubCredentialsFile(fileSystem),
      );
      expect(await store.read(), 'from-prompt');
    },
  );

  test('fails cleanly when the interactive prompt yields nothing', () async {
    final code = await runLogin(
      [],
      httpClient: mockGithubUser(),
      readToken: () => null,
    );

    expect(code, 1);
    expect(logger.errors, anyElement(contains('No token provided')));
  });

  test('warns that FLUPO_GITHUB_TOKEN would take priority if set', () async {
    final code = await runLogin(
      ['--token', 'abc123'],
      httpClient: mockGithubUser(),
      environment: {'FLUPO_GITHUB_TOKEN': 'env-token'},
    );

    expect(code, 0);
    expect(logger.warnings, anyElement(contains('FLUPO_GITHUB_TOKEN')));
  });
}
