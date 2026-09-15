import 'dart:convert';

import 'package:file/file.dart';

abstract class GithubCredentialsStore {
  Future<String?> read();
}

class EnvGithubCredentialsStore implements GithubCredentialsStore {
  const EnvGithubCredentialsStore(this.environment);

  final Map<String, String> environment;

  @override
  Future<String?> read() async => environment['FLUPO_GITHUB_TOKEN'];
}

/// Reads a `{"github_token": "..."}` JSON file, e.g. at
/// `applicationConfigHome('flupo')/credentials.json`. Nothing writes this
/// file yet — that's `flupo login`, a follow-up command — but reading it
/// here means build can already pick up a token placed there by hand.
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
