import 'dart:io';

import 'package:process/process.dart';

class GitRefInfo {
  const GitRefInfo({
    required this.branch,
    required this.commit,
    required this.isDirty,
    required this.hasUnpushedCommits,
  });

  final String branch;
  final String commit;
  final bool isDirty;

  /// False both when there are genuinely no unpushed commits *and* when
  /// there's no upstream configured to compare against — in the latter case
  /// we simply can't tell, so this alone should never be the sole reason a
  /// build is blocked.
  final bool hasUnpushedCommits;
}

class GitRefResolutionException implements Exception {
  const GitRefResolutionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Resolves the branch/commit `flupo build`'s git-ref-based GitHub Actions
/// trigger dispatches, and whether the working tree has changes the remote
/// build wouldn't see (uncommitted, or committed but unpushed).
Future<GitRefInfo> resolveGitRef(
  ProcessManager processManager, {
  required String workingDirectory,
}) async {
  Future<ProcessResult> git(List<String> args) =>
      processManager.run(['git', ...args], workingDirectory: workingDirectory);

  final branchResult = await git(['rev-parse', '--abbrev-ref', 'HEAD']);
  if (branchResult.exitCode != 0) {
    throw GitRefResolutionException(
      'Could not determine the current git branch (is $workingDirectory a '
      'git repository?): ${branchResult.stderr.toString().trim()}',
    );
  }
  final branch = branchResult.stdout.toString().trim();

  final commitResult = await git(['rev-parse', 'HEAD']);
  if (commitResult.exitCode != 0) {
    throw GitRefResolutionException(
      'Could not determine the current commit: ${commitResult.stderr.toString().trim()}',
    );
  }
  final commit = commitResult.stdout.toString().trim();

  final statusResult = await git(['status', '--porcelain']);
  final isDirty = statusResult.stdout.toString().trim().isNotEmpty;

  var hasUnpushedCommits = false;
  final upstreamResult = await git(['rev-parse', '--abbrev-ref', '@{u}']);
  if (upstreamResult.exitCode == 0) {
    final countResult = await git(['rev-list', '@{u}..HEAD', '--count']);
    if (countResult.exitCode == 0) {
      hasUnpushedCommits =
          (int.tryParse(countResult.stdout.toString().trim()) ?? 0) > 0;
    }
  }

  return GitRefInfo(
    branch: branch,
    commit: commit,
    isDirty: isDirty,
    hasUnpushedCommits: hasUnpushedCommits,
  );
}
