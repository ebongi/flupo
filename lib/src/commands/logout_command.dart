import 'package:args/command_runner.dart';
import 'package:file/file.dart';

import '../build/github_credentials_store.dart';
import '../util/logger.dart';

class LogoutCommand extends Command<int> {
  LogoutCommand({required this.fileSystem, required this.logger});

  final FileSystem fileSystem;
  final Logger logger;

  @override
  String get name => 'logout';

  @override
  String get description => 'Removes the GitHub token flupo login stored.';

  @override
  Future<int> run() async {
    final credentialsFile = defaultGithubCredentialsFile(fileSystem);
    if (!await credentialsFile.exists()) {
      logger.info('Not logged in — no stored credentials found.');
      return 0;
    }
    await FileGithubCredentialsStore(credentialsFile).delete();
    logger.info('Removed stored GitHub credentials.');
    return 0;
  }
}
