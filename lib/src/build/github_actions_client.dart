import 'dart:convert';

import 'package:http/http.dart' as http;

class GithubApiException implements Exception {
  const GithubApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GithubRun {
  const GithubRun({
    required this.id,
    required this.name,
    required this.status,
    required this.htmlUrl,
    this.conclusion,
  });

  factory GithubRun.fromJson(Map<String, dynamic> json) => GithubRun(
    id: json['id'] as int,
    name: json['name'] as String? ?? '',
    status: json['status'] as String? ?? 'queued',
    conclusion: json['conclusion'] as String?,
    htmlUrl: json['html_url'] as String? ?? '',
  );

  final int id;
  final String name;

  /// One of GitHub's run statuses: `queued`, `in_progress`, `completed`.
  final String status;

  /// Only set once [status] is `completed`: `success`, `failure`,
  /// `cancelled`, etc.
  final String? conclusion;
  final String htmlUrl;
}

class GithubArtifact {
  const GithubArtifact({
    required this.id,
    required this.name,
    required this.archiveDownloadUrl,
  });

  factory GithubArtifact.fromJson(Map<String, dynamic> json) => GithubArtifact(
    id: json['id'] as int,
    name: json['name'] as String,
    archiveDownloadUrl: Uri.parse(json['archive_download_url'] as String),
  );

  final int id;
  final String name;
  final Uri archiveDownloadUrl;
}

/// A thin wrapper over the subset of the GitHub REST API `flupo build`
/// needs: dispatching a `workflow_dispatch` event, finding the run it
/// created (dispatch itself returns no run id), polling that run's status,
/// and downloading its artifact.
class GithubActionsClient {
  GithubActionsClient({
    required this.httpClient,
    required this.token,
    this.baseUrl = 'https://api.github.com',
  });

  final http.Client httpClient;
  final String token;
  final String baseUrl;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  Future<void> dispatchWorkflow({
    required String repo,
    required String workflowFile,
    required String ref,
    required Map<String, String> inputs,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/repos/$repo/actions/workflows/$workflowFile/dispatches',
    );
    final response = await httpClient.post(
      uri,
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'ref': ref, 'inputs': inputs}),
    );
    if (response.statusCode != 204) {
      throw GithubApiException(
        'Failed to dispatch workflow "$workflowFile" in $repo '
        '(${response.statusCode}): ${response.body}',
      );
    }
  }

  /// GitHub's dispatch call returns no run id, so finding the run it created
  /// means matching on its display name — which requires the target
  /// workflow to set `run-name: "flupo ${{ inputs.correlation_id }}"`.
  Future<GithubRun?> findRunByName({
    required String repo,
    required String workflowFile,
    required String branch,
    required String runName,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/repos/$repo/actions/workflows/$workflowFile/runs',
    ).replace(queryParameters: {'branch': branch, 'per_page': '10'});
    final response = await httpClient.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw GithubApiException(
        'Failed to list workflow runs for $repo (${response.statusCode}): ${response.body}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final runs = (json['workflow_runs'] as List).cast<Map<String, dynamic>>();
    for (final run in runs) {
      if (run['name'] == runName) {
        return GithubRun.fromJson(run);
      }
    }
    return null;
  }

  Future<GithubRun> getRun({required String repo, required int runId}) async {
    final uri = Uri.parse('$baseUrl/repos/$repo/actions/runs/$runId');
    final response = await httpClient.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw GithubApiException(
        'Failed to get workflow run $runId in $repo (${response.statusCode}): ${response.body}',
      );
    }
    return GithubRun.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<GithubArtifact>> listArtifacts({
    required String repo,
    required int runId,
  }) async {
    final uri = Uri.parse('$baseUrl/repos/$repo/actions/runs/$runId/artifacts');
    final response = await httpClient.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw GithubApiException(
        'Failed to list artifacts for run $runId in $repo (${response.statusCode}): ${response.body}',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['artifacts'] as List)
        .cast<Map<String, dynamic>>()
        .map(GithubArtifact.fromJson)
        .toList();
  }

  /// Downloads an artifact's zip bytes.
  ///
  /// GitHub's artifact-download endpoint 302s to a signed, time-limited
  /// blob-storage URL. Letting an HTTP client follow that redirect
  /// automatically re-sends our GitHub `Authorization` header to the storage
  /// backend, which commonly rejects the request — so this follows the
  /// redirect manually and issues a bare, unauthenticated request for the
  /// final URL.
  Future<List<int>> downloadArtifact(GithubArtifact artifact) async {
    final request = http.Request('GET', artifact.archiveDownloadUrl)
      ..followRedirects = false
      ..headers.addAll(_headers);
    final streamedResponse = await httpClient.send(request);

    if (streamedResponse.statusCode != 302) {
      final body = await streamedResponse.stream.bytesToString();
      throw GithubApiException(
        'Expected a redirect to download artifact "${artifact.name}", got '
        '${streamedResponse.statusCode}: $body',
      );
    }

    final location = streamedResponse.headers['location'];
    if (location == null) {
      throw const GithubApiException(
        'Artifact download redirect had no Location header.',
      );
    }

    final finalResponse = await httpClient.get(Uri.parse(location));
    if (finalResponse.statusCode != 200) {
      throw GithubApiException(
        'Failed to download artifact "${artifact.name}" from storage '
        '(${finalResponse.statusCode}).',
      );
    }
    return finalResponse.bodyBytes;
  }
}
