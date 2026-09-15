import 'dart:convert';

import 'package:cli_util/cli_util.dart';
import 'package:file/file.dart';

/// Where `flupo login` writes, and `flupo build`'s [FileGithubCredentialsStore]
/// reads, the GitHub token — one function so both always agree on the path.
File defaultGithubCredentialsFile(FileSystem fileSystem) => fileSystem.file(
  fileSystem.path.join(BaseDirectories('flupo').configHome, 'credentials.json'),
);

abstract class GithubCredentialsStore {
  Future<String?> read();
}

class EnvGithubCredentialsStore implements GithubCredentialsStore {
  const EnvGithubCredentialsStore(this.environment);

  final Map<String, String> environment;

  @override
  Future<String?> read() async => environment['FLUPO_GITHUB_TOKEN'];
}

/// Reads (and, via `flupo login`/`flupo logout`, writes) a
/// `{"github_token": "..."}` JSON file at [defaultGithubCredentialsFile].
class FileGithubCredentialsStore implements GithubCredentialsStore {
  const FileGithubCredentialsStore(this.file);

  final File file;

  @override
  Future<String?> read() async {
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return null;
      final token = json['github_token'];
      return token is String && token.isNotEmpty ? token : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> write(String token) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'github_token': token}));
  }

  Future<void> delete() async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Tries each store in order, returning the first non-empty token found.
class CompositeGithubCredentialsStore implements GithubCredentialsStore {
  const CompositeGithubCredentialsStore(this.stores);

  final List<GithubCredentialsStore> stores;

  @override
  Future<String?> read() async {
    for (final store in stores) {
      final token = await store.read();
      if (token != null && token.isNotEmpty) return token;
    }
    return null;
  }
}
