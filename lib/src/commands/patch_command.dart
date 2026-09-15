import 'package:args/command_runner.dart';
import 'package:file/file.dart';

import '../manifest/flupo_manifest.dart';
import '../patch/android_identifier_patcher.dart';
import '../patch/android_manifest_patcher.dart';
import '../patch/info_plist_patcher.dart';
import '../patch/ios_identifier_patcher.dart';
import '../util/logger.dart';

class PatchCommand extends Command<int> {
  PatchCommand({required this.fileSystem, required this.logger}) {
    argParser
      ..addOption(
        'path',
        help:
            'The Flutter project root to patch (defaults to the current '
            'directory).',
      )
      ..addFlag(
        'dry-run',
        abbr: 'n',
        negatable: false,
        help: 'Show what would change without writing any files.',
      );
  }

  final FileSystem fileSystem;
  final Logger logger;

  @override
  String get name => 'patch';

  @override
  String get description =>
      'Applies flupo.yaml permissions and identifiers to native Android/iOS project files.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final rawPath = results.option('path');
    final projectDir = rawPath == null
        ? fileSystem.currentDirectory
        : fileSystem.directory(
            fileSystem.path.normalize(fileSystem.path.absolute(rawPath)),
          );
    final dryRun = results.flag('dry-run');

    final FlupoManifest manifest;
    try {
      manifest = await FlupoManifest.fromFile(
        projectDir.childFile('flupo.yaml'),
      );
    } on ManifestValidationException catch (e) {
      logger.error(e.toString());
      return 1;
    }

    await _patchAndroid(projectDir, manifest, dryRun: dryRun);
    await _patchIos(projectDir, manifest, dryRun: dryRun);

    return 0;
  }

  Future<void> _patchAndroid(
    Directory projectDir,
    FlupoManifest manifest, {
    required bool dryRun,
  }) async {
    final androidDir = projectDir.childDirectory('android');
    if (!await androidDir.exists()) {
      logger.info('No android/ directory found; skipping Android patches.');
      return;
    }

    final manifestFile = projectDir.childFile(
      'android/app/src/main/AndroidManifest.xml',
    );
    if (await manifestFile.exists()) {
      final original = await manifestFile.readAsString();
      final result = patchAndroidManifest(original, manifest.permissions);
      if (result.changed) {
        await _write(
          manifestFile,
          original: original,
          updated: result.content,
          dryRun: dryRun,
        );
        logger.info(
          '${_verb('Added', dryRun)} ${result.added.length} Android '
          'permission(s) in ${manifestFile.path}: ${result.added.join(', ')}',
        );
      } else {
        logger.info(
          'Android permissions already up to date in ${manifestFile.path}.',
        );
      }
    } else {
      logger.warn(
        '${manifestFile.path} not found; skipping Android permissions.',
      );
    }

    final kotlinGradle = projectDir.childFile('android/app/build.gradle.kts');
    final groovyGradle = projectDir.childFile('android/app/build.gradle');
    File? gradleFile;
    var isKotlinDsl = true;
    if (await kotlinGradle.exists()) {
      gradleFile = kotlinGradle;
      isKotlinDsl = true;
    } else if (await groovyGradle.exists()) {
      gradleFile = groovyGradle;
      isKotlinDsl = false;
    }

    if (gradleFile == null) {
      logger.warn(
        'No android/app/build.gradle(.kts) found; skipping Android identifier patch.',
      );
      return;
    }

    final original = await gradleFile.readAsString();
    final result = patchAndroidApplicationId(
      original,
      isKotlinDsl: isKotlinDsl,
      newIdentifier: manifest.identifier,
    );
    if (result.skippedReason != null) {
      logger.warn('${gradleFile.path}: ${result.skippedReason}');
    } else if (result.changed) {
      await _write(
        gradleFile,
        original: original,
        updated: result.content,
        dryRun: dryRun,
      );
      logger.info(
        '${_verb('Changed', dryRun)} applicationId in ${gradleFile.path}: '
        '${result.previousIdentifier} -> ${manifest.identifier}',
      );
    } else {
      logger.info('applicationId already up to date in ${gradleFile.path}.');
    }
  }

  Future<void> _patchIos(
    Directory projectDir,
    FlupoManifest manifest, {
    required bool dryRun,
  }) async {
    final iosDir = projectDir.childDirectory('ios');
    if (!await iosDir.exists()) {
      logger.info('No ios/ directory found; skipping iOS patches.');
      return;
    }

    final plistFile = projectDir.childFile('ios/Runner/Info.plist');
    if (await plistFile.exists()) {
      final original = await plistFile.readAsString();
      final result = patchInfoPlist(original, manifest.permissions);
      if (result.changed) {
        await _write(
          plistFile,
          original: original,
          updated: result.content,
          dryRun: dryRun,
        );
        logger.info(
          '${_verb('Added', dryRun)} ${result.added.length} iOS usage '
          'description(s) in ${plistFile.path}: ${result.added.join(', ')}',
        );
      } else {
        logger.info(
          'iOS usage descriptions already up to date in ${plistFile.path}.',
        );
      }
    } else {
      logger.warn('${plistFile.path} not found; skipping iOS permissions.');
    }

    final pbxprojFile = projectDir.childFile(
      'ios/Runner.xcodeproj/project.pbxproj',
    );
    if (!await pbxprojFile.exists()) {
      logger.warn(
        '${pbxprojFile.path} not found; skipping iOS identifier patch.',
      );
      return;
    }

    final original = await pbxprojFile.readAsString();
    final result = patchPbxprojBundleIdentifier(original, manifest.identifier);
    if (result.warning != null) {
      logger.warn('${pbxprojFile.path}: ${result.warning}');
    }
    if (result.changed) {
      await _write(
        pbxprojFile,
        original: original,
        updated: result.content,
        dryRun: dryRun,
      );
      logger.info(
        '${_verb('Changed', dryRun)} PRODUCT_BUNDLE_IDENTIFIER in '
        '${pbxprojFile.path}: ${result.previousIdentifier} -> ${result.sanitizedIdentifier}',
      );
    } else if (result.previousIdentifier != null) {
      logger.info(
        'PRODUCT_BUNDLE_IDENTIFIER already up to date in ${pbxprojFile.path}.',
      );
    }
  }

  String _verb(String verb, bool dryRun) =>
      dryRun ? '[dry-run] would be ${verb.toLowerCase()}' : verb;

  Future<void> _write(
    File file, {
    required String original,
    required String updated,
    required bool dryRun,
  }) async {
    if (dryRun) return;
    await fileSystem.file('${file.path}.bak').writeAsString(original);
    await file.writeAsString(updated);
  }
}
