import 'dart:io';

import 'package:archive/archive.dart';
import 'package:args/command_runner.dart';
import 'package:cli_util/cli_util.dart';
import 'package:file/file.dart';
import 'package:http/http.dart' as http;
import 'package:process/process.dart';
import 'package:uuid/uuid.dart';

import '../build/build_runner.dart';
import '../build/git_ref_resolver.dart';
import '../build/github_actions_client.dart';
import '../build/github_actions_runner.dart';
import '../build/github_credentials_store.dart';
import '../build/local_artifact_server.dart';
import '../manifest/flupo_manifest.dart';
import '../util/local_ip.dart';
import '../util/logger.dart';
import '../util/terminal_qr.dart';

class BuildCommand extends Command<int> {
  BuildCommand({
    required this.fileSystem,
    required this.processManager,
    required this.logger,
    http.Client? httpClient,
    GithubCredentialsStore? credentialsStore,
    this.serveDuration = const Duration(minutes: 10),
    Stream<ProcessSignal>? interruptSignal,
  }) : httpClient = httpClient ?? http.Client(),
       credentialsStore =
           credentialsStore ??
           CompositeGithubCredentialsStore([
             EnvGithubCredentialsStore(Platform.environment),
             FileGithubCredentialsStore(
               fileSystem.file(
                 fileSystem.path.join(
                   BaseDirectories('flupo').configHome,
                   'credentials.json',
                 ),
               ),
             ),
           ]),
       interruptSignal = interruptSignal ?? ProcessSignal.sigint.watch() {
    argParser
      ..addOption(
        'path',
        help:
            'The Flutter project root to build (defaults to the current '
            'directory).',
      )
      ..addOption(
        'repo',
        help:
            'GitHub "owner/name" to dispatch the build workflow in '
            '(overrides flupo.yaml build.github.repo).',
      )
      ..addOption(
        'workflow',
        help:
            'Workflow file name to dispatch, e.g. build.yml (overrides '
            'flupo.yaml build.github.workflow).',
      )
      ..addFlag(
        'allow-dirty',
        negatable: false,
        help:
            'Dispatch the build even with uncommitted or unpushed local '
            "changes (the remote build only sees what's pushed).",
      )
      ..addFlag(
        'install',
        negatable: false,
        help:
            'Install the downloaded artifact via `adb install -r` if '
            'exactly one Android device is connected.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help:
            'Directory to save the downloaded artifact into (defaults to '
            'the project root).',
      );
  }

  final FileSystem fileSystem;
  final ProcessManager processManager;
  final Logger logger;
  final http.Client httpClient;
  final GithubCredentialsStore credentialsStore;
  final Duration serveDuration;
  final Stream<ProcessSignal> interruptSignal;

  @override
  String get name => 'build';

  @override
  String get description =>
      'Dispatches a GitHub Actions build for this project and downloads the result.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final rawPath = results.option('path');
    final projectDir = rawPath == null
        ? fileSystem.currentDirectory
        : fileSystem.directory(
            fileSystem.path.normalize(fileSystem.path.absolute(rawPath)),
          );

    final FlupoManifest manifest;
    try {
      manifest = await FlupoManifest.fromFile(
        projectDir.childFile('flupo.yaml'),
      );
    } on ManifestValidationException catch (e) {
      logger.error(e.toString());
      return 1;
    }

    if (manifest.build.runner != 'github_actions') {
      logger.error(
        'Unsupported build runner "${manifest.build.runner}". Only '
        '"github_actions" is implemented.',
      );
      return 1;
    }

    final repo = results.option('repo') ?? manifest.build.githubRepo;
    final workflow =
        results.option('workflow') ?? manifest.build.githubWorkflow;
    if (repo == null || workflow == null) {
      logger.error(
        'Missing GitHub target. Set build.github.repo and '
        'build.github.workflow in flupo.yaml, or pass --repo and --workflow.',
      );
      return 1;
    }

    final token = await credentialsStore.read();
    if (token == null) {
      logger.error(
        'No GitHub token found. Set the FLUPO_GITHUB_TOKEN environment '
        'variable to a personal access token with the "workflow" scope, or '
        'place one at ${fileSystem.path.join(BaseDirectories('flupo').configHome, 'credentials.json')} '
        'as {"github_token": "..."}.',
      );
      return 1;
    }

    final GitRefInfo gitInfo;
    try {
      gitInfo = await resolveGitRef(
        processManager,
        workingDirectory: projectDir.path,
      );
    } on GitRefResolutionException catch (e) {
      logger.error(e.toString());
      return 1;
    }

    if (!results.flag('allow-dirty') &&
        (gitInfo.isDirty || gitInfo.hasUnpushedCommits)) {
      final problems = [
        if (gitInfo.isDirty) 'has uncommitted changes',
        if (gitInfo.hasUnpushedCommits)
          'has commits not pushed to its upstream',
      ].join(' and ');
      logger.error(
        'The working tree $problems — the remote build only sees what\'s '
        'pushed to GitHub. Commit and push first, or pass --allow-dirty to '
        'build ${gitInfo.commit.substring(0, 7)} anyway.',
      );
      return 1;
    }

    final correlationId = const Uuid().v4();
    final client = GithubActionsClient(httpClient: httpClient, token: token);
    final runner = GithubActionsRunner(
      client: client,
      repo: repo,
      workflowFile: workflow,
    );
    final request = BuildRequest(
      target: manifest.build.target,
      ref: gitInfo.branch,
      commit: gitInfo.commit,
      correlationId: correlationId,
    );

    logger.info(
      'Dispatching ${manifest.build.target} build for $repo@${gitInfo.branch} '
      '(${gitInfo.commit.substring(0, 7)})...',
    );

    final BuildHandle handle;
    String? conclusion;
    try {
      handle = await runner.trigger(request);
      logger.info('Watching run: ${handle.htmlUrl}');
      await for (final event in runner.watch(handle)) {
        logger.info(
          'Status: ${event.status.name}${event.conclusion != null ? ' (${event.conclusion})' : ''}',
        );
        conclusion = event.conclusion;
      }
    } on GithubApiException catch (e) {
      logger.error(e.toString());
      return 1;
    }

    if (conclusion != 'success') {
      logger.error(
        'Build did not succeed (conclusion: $conclusion). See ${handle.htmlUrl}.',
      );
      return 1;
    }

    final List<int> zipBytes;
    try {
      zipBytes = await runner.downloadArtifact(handle);
    } on GithubApiException catch (e) {
      logger.error(e.toString());
      return 1;
    }

    final extracted = _extractArtifact(zipBytes, manifest.build.target);
    if (extracted == null) {
      logger.error(
        'Downloaded artifact did not contain a .${_extensionFor(manifest.build.target)} file.',
      );
      return 1;
    }

    final outputDirOption = results.option('output');
    final outputDir = outputDirOption == null
        ? projectDir
        : fileSystem.directory(
            fileSystem.path.normalize(
              fileSystem.path.absolute(outputDirOption),
            ),
          );
    await outputDir.create(recursive: true);
    final artifactFile = outputDir.childFile(
      fileSystem.path.basename(extracted.name),
    );
    await artifactFile.writeAsBytes(extracted.content as List<int>);
    logger.info('Saved artifact to ${artifactFile.path}');

    final server = await LocalArtifactServer.serve(artifactFile);
    final host = await detectLocalIp() ?? 'localhost';
    final url = server.urlFor(host);
    logger.info('Download it on your phone: $url');
    logger.info(renderTerminalQr(url.toString()));
    logger.info(
      'Serving for up to ${serveDuration.inMinutes} minute(s) — press Ctrl+C to stop early.',
    );

    if (results.flag('install')) {
      await _tryAdbInstall(artifactFile.path);
    }

    await Future.any([
      Future<void>.delayed(serveDuration),
      interruptSignal.first,
    ]);
    await server.close();

    return 0;
  }

  ArchiveFile? _extractArtifact(List<int> zipBytes, String target) {
    final extension = '.${_extensionFor(target)}';
    final archive = ZipDecoder().decodeBytes(zipBytes);
    for (final file in archive.files) {
      if (file.isFile && file.name.toLowerCase().endsWith(extension)) {
        return file;
      }
    }
    return null;
  }

  String _extensionFor(String target) => switch (target) {
    'apk' => 'apk',
    'appbundle' => 'aab',
    'ipa' => 'ipa',
    _ => target,
  };

  Future<void> _tryAdbInstall(String artifactPath) async {
    final devicesResult = await processManager.run(['adb', 'devices']);
    if (devicesResult.exitCode != 0) {
      logger.warn('Could not run `adb devices`; skipping --install.');
      return;
    }
    final connected = devicesResult.stdout
        .toString()
        .split('\n')
        .skip(1)
        .where((line) => line.trim().endsWith('device'))
        .toList();

    if (connected.isEmpty) {
      logger.warn('--install requested but no adb device is connected.');
      return;
    }
    if (connected.length > 1) {
      logger.warn(
        '--install requested but multiple adb devices are connected; '
        'install manually with `adb -s <serial> install -r $artifactPath`.',
      );
      return;
    }

    final installResult = await processManager.run([
      'adb',
      'install',
      '-r',
      artifactPath,
    ]);
    if (installResult.exitCode == 0) {
      logger.info('Installed on the connected device.');
    } else {
      logger.warn('adb install failed: ${installResult.stderr}');
    }
  }
}
