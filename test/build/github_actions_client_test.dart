import 'dart:convert';

import 'package:flupo/src/build/github_actions_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('dispatchWorkflow', () {
    test('succeeds on a 204 response', () async {
      http.Request? captured;
      final client = GithubActionsClient(
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response('', 204);
        }),
        token: 'test-token',
      );

      await client.dispatchWorkflow(
        repo: 'acme/app',
        workflowFile: 'build.yml',
        ref: 'main',
        inputs: {'target': 'apk'},
      );

      expect(
        captured!.url.toString(),
        'https://api.github.com/repos/acme/app/actions/workflows/build.yml/dispatches',
      );
      expect(captured!.headers['Authorization'], 'Bearer test-token');
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['ref'], 'main');
      expect(body['inputs'], {'target': 'apk'});
    });

    test('throws GithubApiException on a non-204 response', () async {
      final client = GithubActionsClient(
        httpClient: MockClient((request) async {
          return http.Response('nope', 404);
        }),
        token: 'test-token',
      );

      expect(
        () => client.dispatchWorkflow(
          repo: 'acme/app',
          workflowFile: 'build.yml',
          ref: 'main',
          inputs: const {},
        ),
        throwsA(isA<GithubApiException>()),
      );
    });
  });

  group('findRunByName', () {
    test('returns the run whose name matches', () async {
      final client = GithubActionsClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'workflow_runs': [
                {
                  'id': 1,
                  'name': 'some other run',
                  'status': 'queued',
                  'html_url': 'https://github.com/acme/app/actions/runs/1',
                },
                {
                  'id': 2,
                  'name': 'flupo abc-123',
                  'status': 'queued',
                  'html_url': 'https://github.com/acme/app/actions/runs/2',
                },
              ],
            }),
            200,
          );
        }),
        token: 'test-token',
      );

      final run = await client.findRunByName(
        repo: 'acme/app',
        workflowFile: 'build.yml',
        branch: 'main',
        runName: 'flupo abc-123',
      );

      expect(run, isNotNull);
      expect(run!.id, 2);
    });

    test('returns null when no run matches', () async {
      final client = GithubActionsClient(
        httpClient: MockClient((request) async {
          return http.Response(jsonEncode({'workflow_runs': []}), 200);
        }),
        token: 'test-token',
      );

      final run = await client.findRunByName(
        repo: 'acme/app',
        workflowFile: 'build.yml',
        branch: 'main',
        runName: 'flupo abc-123',
      );

      expect(run, isNull);
    });
  });

  group('getRun', () {
    test('parses status and conclusion', () async {
      final client = GithubActionsClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'id': 42,
              'name': 'flupo abc-123',
              'status': 'completed',
              'conclusion': 'success',
              'html_url': 'https://github.com/acme/app/actions/runs/42',
            }),
            200,
          );
        }),
        token: 'test-token',
      );

      final run = await client.getRun(repo: 'acme/app', runId: 42);

      expect(run.status, 'completed');
      expect(run.conclusion, 'success');
    });
  });

  group('listArtifacts', () {
    test('parses artifact entries', () async {
      final client = GithubActionsClient(
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'artifacts': [
                {
                  'id': 7,
                  'name': 'app-release',
                  'archive_download_url':
                      'https://api.github.com/repos/acme/app/actions/artifacts/7/zip',
                },
              ],
            }),
            200,
          );
        }),
        token: 'test-token',
      );

      final artifacts = await client.listArtifacts(repo: 'acme/app', runId: 42);

      expect(artifacts, hasLength(1));
      expect(artifacts.single.name, 'app-release');
    });
  });

  group('downloadArtifact', () {
    test(
      'follows the redirect without forwarding the Authorization header',
      () async {
        final zipBytes = [1, 2, 3, 4];
        final downloadUri = Uri.parse(
          'https://api.github.com/repos/acme/app/actions/artifacts/7/zip',
        );
        final signedUri = Uri.parse('https://blob.example.com/signed?sig=abc');

        final client = GithubActionsClient(
          httpClient: MockClient((request) async {
            if (request.url == downloadUri) {
              expect(request.headers['Authorization'], 'Bearer test-token');
              return http.Response(
                '',
                302,
                headers: {'location': signedUri.toString()},
              );
            }
            if (request.url == signedUri) {
              expect(request.headers.containsKey('Authorization'), isFalse);
              return http.Response.bytes(zipBytes, 200);
            }
            return http.Response('unexpected request', 500);
          }),
          token: 'test-token',
        );

        final bytes = await client.downloadArtifact(
          GithubArtifact(
            id: 7,
            name: 'app-release',
            archiveDownloadUrl: downloadUri,
          ),
        );

        expect(bytes, zipBytes);
      },
    );

    test('throws when the download endpoint does not redirect', () async {
      final client = GithubActionsClient(
        httpClient: MockClient((request) async => http.Response('nope', 404)),
        token: 'test-token',
      );

      expect(
        () => client.downloadArtifact(
          GithubArtifact(
            id: 7,
            name: 'app-release',
            archiveDownloadUrl: Uri.parse('https://api.github.com/x'),
          ),
        ),
        throwsA(isA<GithubApiException>()),
      );
    });
  });
}
