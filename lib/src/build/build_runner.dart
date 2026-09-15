class BuildRequest {
  const BuildRequest({
    required this.target,
    required this.ref,
    required this.commit,
    required this.correlationId,
  });

  final String target;
  final String ref;
  final String commit;
  final String correlationId;
}

class BuildHandle {
  const BuildHandle({required this.runId, required this.htmlUrl});

  final int runId;
  final String htmlUrl;
}

enum BuildRunStatus { queued, inProgress, completed, unknown }

class BuildStatusEvent {
  const BuildStatusEvent({required this.status, this.conclusion});

  final BuildRunStatus status;

  /// Only set once [status] is [BuildRunStatus.completed].
  final String? conclusion;
}

/// The seam between `flupo build`'s local half (git ref resolution,
/// credential lookup, artifact handling) and whichever remote build backend
/// actually compiles the project. [GithubActionsRunner] is the only
/// implementation for now; a future Codemagic/other-runner backend would
/// implement this same interface.
abstract class BuildRunner {
  Future<BuildHandle> trigger(BuildRequest request);

  /// Emits one event per status transition and completes after the final
  /// (`completed`) event.
  Stream<BuildStatusEvent> watch(BuildHandle handle);

  Future<List<int>> downloadArtifact(BuildHandle handle);
}
