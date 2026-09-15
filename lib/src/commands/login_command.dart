import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:http/http.dart' as http;
import 'package:process/process.dart';

import '../build/github_credentials_store.dart';
import '../util/logger.dart';

class LoginCommand extends Command<int> {
  LoginCommand({
    required this.fileSystem,
    required this.processManager,
    required this.logger,
    http.Client? httpClient,
    String? Function()? readToken,
    Map<String, String>? environment,
  }) : httpClient = httpClient ?? http.Client(),
       readToken = readToken ?? _readTokenFromTerminal,
       environment = environment ?? Platform.environment {
    argParser.addOption(
      'token',
      help:
          'Provide the token directly instead of an interactive prompt '
          '(e.g. for scripts/CI).',
    );
  }

  final FileSystem fileSystem;
  final ProcessManager processManager;
  final Logger logger;
  final http.Client httpClient;
  final String? Function() readToken;
  final Map<String, String> environment;

  @override
  String get name => 'login';

  @override
  String get description =>
      'Stores a GitHub personal access token so flupo build can use it '
      'without setting FLUPO_GITHUB_TOKEN.';

  @override
  Future<int> run() async {
    final results = argResults!;
    var token = results.option('token');

    if (token == null) {
      logger.info(
        'Create a token at https://github.com/settings/tokens/new'
        '?scopes=workflow&description=flupo (needs the "workflow" scope).',
      );
      logger.info('Paste the token and press Enter:');
      token = readToken()?.trim();
    }

    if (token == null || token.isEmpty) {
      logger.error('No token provided.');
      return 1;
    }

    final http.Response response;
    try {
      response = await httpClient.get(
        Uri.parse('https://api.github.com/user'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );
    } on Exception catch (e) {
      logger.error('Could not reach GitHub to validate the token: $e');
      return 1;
    }

    if (response.statusCode != 200) {
      logger.error(
        'GitHub rejected that token (${response.statusCode}). Check it is '
        'valid and not expired.',
      );
      return 1;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final login = body['login'] as String?;

    final scopesHeader = response.headers['x-oauth-scopes'];
    if (scopesHeader != null &&
        !scopesHeader.split(',').map((s) => s.trim()).contains('workflow')) {
      logger.warn(
        'This token does not have the "workflow" scope, which flupo build '
        'needs to dispatch GitHub Actions runs.',
      );
    }

    final credentialsFile = defaultGithubCredentialsFile(fileSystem);
    await FileGithubCredentialsStore(credentialsFile).write(token);
    await _restrictPermissions(credentialsFile.path);

    logger.info(
      'Saved${login != null ? ' — logged in to GitHub as $login' : ''}.',
    );

    if (environment['FLUPO_GITHUB_TOKEN'] != null) {
      logger.warn(
        'FLUPO_GITHUB_TOKEN is currently set in your environment and takes '
        'priority over the token just saved — unset it to use this one.',
      );
    }

    return 0;
  }

  Future<void> _restrictPermissions(String path) async {
    if (Platform.isWindows) return;
    try {
      await processManager.run(['chmod', '600', path]);
    } catch (_) {
      // Best-effort only.
    }
  }

  static String? _readTokenFromTerminal() {
    final hasTerminal = stdin.hasTerminal;
    if (hasTerminal) {
      try {
        stdin.echoMode = false;
      } catch (_) {
        // Fall back to a visible prompt if the terminal doesn't support it.
      }
    }
    try {
      return stdin.readLineSync();
    } finally {
      if (hasTerminal) {
        try {
          stdin.echoMode = true;
        } catch (_) {}
        stdout.writeln();
      }
    }
  }
}
