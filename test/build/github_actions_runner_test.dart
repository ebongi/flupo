import 'dart:convert';

import 'package:flupo/src/build/build_runner.dart';
import 'package:flupo/src/build/github_actions_client.dart';
import 'package:flupo/src/build/github_actions_runner.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('trigger', () {
    test('dispatches and returns the matching run once found', () async {
      var listCalls = 0;
      final client = GithubActionsClient(
        httpClient: MockClient((request) async {
          if (request.method == 'POST') {
            return http.Response('', 204);
          }
          listCalls++;
          final runs = listCalls < 2
              ? []
              : [
                  {
                    'id': 99,
                    'name': 'flupo abc-123',
                    'status': 'queued',
                    'html_url': 'https://github.com/acme/app/actions/runs/99',
                  },
                ];
          return http.Response(jsonEncode({'workflow_runs': runs}), 200);
        }),
        token: 'test-token',
      );
      final runner = GithubActionsRunner(
        client: client,
        repo: 'acme/app',
        workflowFile: 'build.yml',
        pollInterval: Duration.zero,
      );

      final handle = await runner.trigger(
        const BuildRequest(
          target: 'apk',
          ref: 'main',
          commit: 'deadbeef',
          correlationId: 'abc-123',
        ),
      );

      expect(handle.runId, 99);
      expect(listCalls, greaterThanOrEqualTo(2));
    });

    test('times out if the run never appears', () async {
      final client = GithubActionsClient(
        httpClient: MockClient((request) async {
          if (request.method == 'POST') return http.Response('', 204);
          return http.Response(jsonEncode({'workflow_runs': []}), 200);
        }),
        token: 'test-token',
      );
      final runner = GithubActionsRunner(
        client: client,
        repo: 'acme/app',
        workflowFile: 'build.yml',
        pollInterval: Duration.zero,
        findRunTimeout: Duration.zero,
      );

      expect(
        () => runner.trigger(
          const BuildRequest(
            target: 'apk',
            ref: 'main',
            commit: 'deadbeef',
            correlationId: 'abc-123',
          ),
        ),
        throwsA(isA<GithubApiException>()),
      );
    });
  });

  group('watch', () {
    test(
      'yields one event per status transition and stops at completed',
      () async {
        final statuses = ['queued', 'in_progress', 'in_progress', 'completed'];
        var call = 0;
        final client = GithubActionsClient(
          httpClient: MockClient((request) async {
            final status = statuses[call.clamp(0, statuses.length - 1)];
            call++;
            return http.Response(
              jsonEncode({
                'id': 1,
                'name': 'flupo abc-123',
                'status': status,
                'conclusion': status == 'completed' ? 'success' : null,
                'html_url': 'https://github.com/acme/app/actions/runs/1',
              }),
              200,
            );
          }),
          token: 'test-token',
        );
        final runner = GithubActionsRunner(
          client: client,
          repo: 'acme/app',
          workflowFile: 'build.yml',
          pollInterval: Duration.zero,
        );

        final events = await runner
            .watch(const BuildHandle(runId: 1, htmlUrl: 'https://x'))
            .toList();

        expect(events.map((e) => e.status), [
          BuildRunStatus.queued,
          BuildRunStatus.inProgress,
          BuildRunStatus.completed,
        ]);
        expect(events.last.conclusion, 'success');
      },
    );
  });

  group('downloadArtifact', () {
    test('throws when the run produced no artifacts', () async {
      final client = GithubActionsClient(
        httpClient: MockClient((request) async {
          return http.Response(jsonEncode({'artifacts': []}), 200);
        }),
        token: 'test-token',
      );
      final runner = GithubActionsRunner(
        client: client,
        repo: 'acme/app',
        workflowFile: 'build.yml',
      );

      expect(
        () => runner.downloadArtifact(
          const BuildHandle(runId: 1, htmlUrl: 'https://x'),
        ),
        throwsA(isA<GithubApiException>()),
      );
    });
  });
}
