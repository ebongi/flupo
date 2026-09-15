import 'build_runner.dart';
import 'github_actions_client.dart';

class GithubActionsRunner implements BuildRunner {
  GithubActionsRunner({
    required this.client,
    required this.repo,
    required this.workflowFile,
    this.pollInterval = const Duration(seconds: 5),
    this.findRunTimeout = const Duration(seconds: 30),
  });

  final GithubActionsClient client;
  final String repo;
  final String workflowFile;
  final Duration pollInterval;
  final Duration findRunTimeout;

  @override
  Future<BuildHandle> trigger(BuildRequest request) async {
    final runName = 'flupo ${request.correlationId}';
    await client.dispatchWorkflow(
      repo: repo,
      workflowFile: workflowFile,
      ref: request.ref,
      inputs: {
        'ref': request.ref,
        'commit': request.commit,
        'target': request.target,
        'correlation_id': request.correlationId,
      },
    );

    final deadline = DateTime.now().add(findRunTimeout);
    while (true) {
      final run = await client.findRunByName(
        repo: repo,
        workflowFile: workflowFile,
        branch: request.ref,
        runName: runName,
      );
      if (run != null) {
        return BuildHandle(runId: run.id, htmlUrl: run.htmlUrl);
      }
      if (DateTime.now().isAfter(deadline)) {
        throw GithubApiException(
          'Timed out waiting for GitHub to register the dispatched run '
          '"$runName". Make sure your workflow sets '
          r'`run-name: "flupo ${{ inputs.correlation_id }}"`.',
        );
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  @override
  Stream<BuildStatusEvent> watch(BuildHandle handle) async* {
    BuildRunStatus? lastStatus;
    while (true) {
      final run = await client.getRun(repo: repo, runId: handle.runId);
      final status = _mapStatus(run.status);
      if (status != lastStatus) {
        yield BuildStatusEvent(status: status, conclusion: run.conclusion);
        lastStatus = status;
      }
      if (status == BuildRunStatus.completed) return;
      await Future<void>.delayed(pollInterval);
    }
  }

  @override
  Future<List<int>> downloadArtifact(BuildHandle handle) async {
    final artifacts = await client.listArtifacts(
      repo: repo,
      runId: handle.runId,
    );
    if (artifacts.isEmpty) {
      throw GithubApiException(
        'Workflow run ${handle.runId} produced no artifacts.',
      );
    }
    return client.downloadArtifact(artifacts.first);
  }

  BuildRunStatus _mapStatus(String status) => switch (status) {
    'queued' => BuildRunStatus.queued,
    'in_progress' => BuildRunStatus.inProgress,
    'completed' => BuildRunStatus.completed,
    _ => BuildRunStatus.unknown,
  };
}
