import 'dart:io';

import 'package:flupo/src/build/git_ref_resolver.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../support/mocks.dart';

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');
ProcessResult _fail(String stderr) => ProcessResult(0, 1, '', stderr);

void main() {
  late MockProcessManager processManager;

  setUp(() => processManager = MockProcessManager());

  void stubGit(Map<List<String>, ProcessResult> responses) {
    when(
      () => processManager.run(
        any(),
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((invocation) async {
      final command = (invocation.positionalArguments.first as List<Object?>)
          .cast<String>();
      final args = command.skip(1).toList();
      for (final entry in responses.entries) {
        if (entry.key.join(' ') == args.join(' ')) return entry.value;
      }
      throw UnsupportedError('Unexpected git command: $args');
    });
  }

  test('resolves branch, commit, and clean/pushed state', () async {
    stubGit({
      ['rev-parse', '--abbrev-ref', 'HEAD']: _ok('main\n'),
      ['rev-parse', 'HEAD']: _ok('deadbeefcafe\n'),
      ['status', '--porcelain']: _ok(''),
      ['rev-parse', '--abbrev-ref', '@{u}']: _ok('origin/main\n'),
      ['rev-list', '@{u}..HEAD', '--count']: _ok('0\n'),
    });

    final info = await resolveGitRef(
      processManager,
      workingDirectory: '/project',
    );

    expect(info.branch, 'main');
    expect(info.commit, 'deadbeefcafe');
    expect(info.isDirty, isFalse);
    expect(info.hasUnpushedCommits, isFalse);
  });

  test('detects a dirty working tree', () async {
    stubGit({
      ['rev-parse', '--abbrev-ref', 'HEAD']: _ok('main\n'),
      ['rev-parse', 'HEAD']: _ok('deadbeefcafe\n'),
      ['status', '--porcelain']: _ok(' M lib/foo.dart\n'),
      ['rev-parse', '--abbrev-ref', '@{u}']: _ok('origin/main\n'),
      ['rev-list', '@{u}..HEAD', '--count']: _ok('0\n'),
    });

    final info = await resolveGitRef(
      processManager,
      workingDirectory: '/project',
    );

    expect(info.isDirty, isTrue);
  });

  test('detects unpushed commits', () async {
    stubGit({
      ['rev-parse', '--abbrev-ref', 'HEAD']: _ok('main\n'),
      ['rev-parse', 'HEAD']: _ok('deadbeefcafe\n'),
      ['status', '--porcelain']: _ok(''),
      ['rev-parse', '--abbrev-ref', '@{u}']: _ok('origin/main\n'),
      ['rev-list', '@{u}..HEAD', '--count']: _ok('2\n'),
    });

    final info = await resolveGitRef(
      processManager,
      workingDirectory: '/project',
    );

    expect(info.hasUnpushedCommits, isTrue);
  });

  test('treats a missing upstream as unknown, not unpushed', () async {
    stubGit({
      ['rev-parse', '--abbrev-ref', 'HEAD']: _ok('main\n'),
      ['rev-parse', 'HEAD']: _ok('deadbeefcafe\n'),
      ['status', '--porcelain']: _ok(''),
      ['rev-parse', '--abbrev-ref', '@{u}']: _fail('no upstream configured'),
    });

    final info = await resolveGitRef(
      processManager,
      workingDirectory: '/project',
    );

    expect(info.hasUnpushedCommits, isFalse);
  });

  test('throws a clear error when not a git repository', () async {
    stubGit({
      ['rev-parse', '--abbrev-ref', 'HEAD']: _fail('not a git repository'),
    });

    expect(
      () => resolveGitRef(processManager, workingDirectory: '/project'),
      throwsA(isA<GitRefResolutionException>()),
    );
  });
}
