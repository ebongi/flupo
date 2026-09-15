import 'package:file/memory.dart';
import 'package:flupo/src/build/github_credentials_store.dart';
import 'package:test/test.dart';

void main() {
  group('EnvGithubCredentialsStore', () {
    test('reads FLUPO_GITHUB_TOKEN from the given environment', () async {
      final store = EnvGithubCredentialsStore({'FLUPO_GITHUB_TOKEN': 'abc123'});
      expect(await store.read(), 'abc123');
    });

    test('returns null when unset', () async {
      final store = EnvGithubCredentialsStore(const {});
      expect(await store.read(), isNull);
    });
  });

  group('FileGithubCredentialsStore', () {
    test('returns null when the file does not exist', () async {
      final fs = MemoryFileSystem();
      final store = FileGithubCredentialsStore(
        fs.file('/config/credentials.json'),
      );
      expect(await store.read(), isNull);
    });

    test('returns null on malformed JSON', () async {
      final fs = MemoryFileSystem();
      fs.file('/config/credentials.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('not json');
      final store = FileGithubCredentialsStore(
        fs.file('/config/credentials.json'),
      );
      expect(await store.read(), isNull);
    });

    test('returns null when github_token is missing or empty', () async {
      final fs = MemoryFileSystem();
      fs.file('/config/credentials.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"github_token": ""}');
      final store = FileGithubCredentialsStore(
        fs.file('/config/credentials.json'),
      );
      expect(await store.read(), isNull);
    });

    test('reads a valid token', () async {
      final fs = MemoryFileSystem();
      fs.file('/config/credentials.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"github_token": "abc123"}');
      final store = FileGithubCredentialsStore(
        fs.file('/config/credentials.json'),
      );
      expect(await store.read(), 'abc123');
    });
  });

  group('CompositeGithubCredentialsStore', () {
    test('returns the first non-empty token, in order', () async {
      final store = CompositeGithubCredentialsStore([
        EnvGithubCredentialsStore(const {}),
        EnvGithubCredentialsStore({'FLUPO_GITHUB_TOKEN': 'from-second'}),
        EnvGithubCredentialsStore({'FLUPO_GITHUB_TOKEN': 'from-third'}),
      ]);

      expect(await store.read(), 'from-second');
    });

    test('returns null when every store is empty', () async {
      final store = CompositeGithubCredentialsStore([
        EnvGithubCredentialsStore(const {}),
        EnvGithubCredentialsStore(const {}),
      ]);

      expect(await store.read(), isNull);
    });
  });
}
