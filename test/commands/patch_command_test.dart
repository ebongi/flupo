import 'package:file/memory.dart';
import 'package:flupo/src/command_runner.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';
import '../support/mocks.dart';
import '../support/recording_logger.dart';

void main() {
  late MemoryFileSystem fileSystem;
  late RecordingLogger logger;

  setUp(() {
    fileSystem = MemoryFileSystem();
    logger = RecordingLogger();
    fileSystem.directory('/project').createSync(recursive: true);
    fileSystem.currentDirectory = '/project';
  });

  FlupoCommandRunner buildRunner() => FlupoCommandRunner(
    fileSystem: fileSystem,
    processManager: MockProcessManager(),
    logger: logger,
  );

  void writeManifest() {
    fileSystem.file('/project/flupo.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
name: flupo_go
version: 1.0.0+1
identifier: com.acme.myapp
permissions:
  camera: "Need camera access"
build:
  target: apk
  runner: github_actions
''');
  }

  void writeAndroidProject() {
    fileSystem.file('/project/android/app/src/main/AndroidManifest.xml')
      ..createSync(recursive: true)
      ..writeAsStringSync(readFixture('android_manifest_before.xml'));
    fileSystem.file('/project/android/app/build.gradle.kts')
      ..createSync(recursive: true)
      ..writeAsStringSync(readFixture('build_gradle_kts_before.txt'));
  }

  void writeIosProject() {
    fileSystem.file('/project/ios/Runner/Info.plist')
      ..createSync(recursive: true)
      ..writeAsStringSync(readFixture('info_plist_before.plist'));
    fileSystem.file('/project/ios/Runner.xcodeproj/project.pbxproj')
      ..createSync(recursive: true)
      ..writeAsStringSync(readFixture('project_pbxproj_before.txt'));
  }

  test('fails cleanly when flupo.yaml is missing', () async {
    final code = await buildRunner().runFlupo(['patch']);

    expect(code, 1);
    expect(logger.errors.single, contains('Run `flupo init` first'));
  });

  test('patches Android and iOS permissions and identifiers', () async {
    writeManifest();
    writeAndroidProject();
    writeIosProject();

    final code = await buildRunner().runFlupo(['patch']);

    expect(code, 0);

    expect(
      fileSystem
          .file('/project/android/app/src/main/AndroidManifest.xml')
          .readAsStringSync(),
      contains('android.permission.CAMERA'),
    );
    expect(
      fileSystem
          .file('/project/android/app/build.gradle.kts')
          .readAsStringSync(),
      contains('applicationId = "com.acme.myapp"'),
    );
    expect(
      fileSystem.file('/project/ios/Runner/Info.plist').readAsStringSync(),
      contains('NSCameraUsageDescription'),
    );
    expect(
      fileSystem
          .file('/project/ios/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync(),
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.acme.myapp;'),
    );

    expect(
      fileSystem
          .file('/project/android/app/src/main/AndroidManifest.xml.bak')
          .existsSync(),
      isTrue,
    );
    expect(
      fileSystem.file('/project/android/app/build.gradle.kts.bak').existsSync(),
      isTrue,
    );
    expect(
      fileSystem.file('/project/ios/Runner/Info.plist.bak').existsSync(),
      isTrue,
    );
    expect(
      fileSystem
          .file('/project/ios/Runner.xcodeproj/project.pbxproj.bak')
          .existsSync(),
      isTrue,
    );
  });

  test('--dry-run writes nothing', () async {
    writeManifest();
    writeAndroidProject();

    final code = await buildRunner().runFlupo(['patch', '--dry-run']);

    expect(code, 0);
    expect(
      fileSystem
          .file('/project/android/app/src/main/AndroidManifest.xml')
          .readAsStringSync(),
      readFixture('android_manifest_before.xml'),
    );
    expect(
      fileSystem
          .file('/project/android/app/src/main/AndroidManifest.xml.bak')
          .existsSync(),
      isFalse,
    );
    expect(logger.infos, anyElement(contains('[dry-run]')));
  });

  test('skips Android/iOS gracefully when the folders are absent', () async {
    writeManifest();

    final code = await buildRunner().runFlupo(['patch']);

    expect(code, 0);
    expect(logger.infos, anyElement(contains('No android/ directory found')));
    expect(logger.infos, anyElement(contains('No ios/ directory found')));
  });

  test(
    'running patch twice is idempotent (no duplicate permission blocks)',
    () async {
      writeManifest();
      writeAndroidProject();

      await buildRunner().runFlupo(['patch']);
      final afterFirst = fileSystem
          .file('/project/android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();

      final code = await buildRunner().runFlupo(['patch']);
      final afterSecond = fileSystem
          .file('/project/android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();

      expect(code, 0);
      expect(afterSecond, afterFirst);
      expect('android.permission.CAMERA'.allMatches(afterSecond).length, 1);
    },
  );

  test(
    'without --prune, a permission removed from flupo.yaml is left in place',
    () async {
      writeManifest();
      writeAndroidProject();
      writeIosProject();
      await buildRunner().runFlupo(['patch']);

      fileSystem.file('/project/flupo.yaml').writeAsStringSync('''
name: flupo_go
version: 1.0.0+1
identifier: com.acme.myapp
permissions: {}
build:
  target: apk
  runner: github_actions
''');
      final code = await buildRunner().runFlupo(['patch']);

      expect(code, 0);
      expect(
        fileSystem
            .file('/project/android/app/src/main/AndroidManifest.xml')
            .readAsStringSync(),
        contains('android.permission.CAMERA'),
      );
      expect(
        fileSystem.file('/project/ios/Runner/Info.plist').readAsStringSync(),
        contains('NSCameraUsageDescription'),
      );
    },
  );

  test('--prune removes a permission no longer in flupo.yaml', () async {
    writeManifest();
    writeAndroidProject();
    writeIosProject();
    await buildRunner().runFlupo(['patch']);

    fileSystem.file('/project/flupo.yaml').writeAsStringSync('''
name: flupo_go
version: 1.0.0+1
identifier: com.acme.myapp
permissions: {}
build:
  target: apk
  runner: github_actions
''');
    final code = await buildRunner().runFlupo(['patch', '--prune']);

    expect(code, 0);
    expect(
      fileSystem
          .file('/project/android/app/src/main/AndroidManifest.xml')
          .readAsStringSync(),
      isNot(contains('android.permission.CAMERA')),
    );
    expect(
      fileSystem.file('/project/ios/Runner/Info.plist').readAsStringSync(),
      isNot(contains('NSCameraUsageDescription')),
    );
    expect(
      logger.infos,
      anyElement(
        allOf(contains('remove'), contains('android.permission.CAMERA')),
      ),
    );
  });

  test('--prune --dry-run reports removals without writing them', () async {
    writeManifest();
    writeAndroidProject();
    await buildRunner().runFlupo(['patch']);
    final afterFirstPatch = fileSystem
        .file('/project/android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    fileSystem.file('/project/flupo.yaml').writeAsStringSync('''
name: flupo_go
version: 1.0.0+1
identifier: com.acme.myapp
permissions: {}
build:
  target: apk
  runner: github_actions
''');
    final code = await buildRunner().runFlupo([
      'patch',
      '--prune',
      '--dry-run',
    ]);

    expect(code, 0);
    expect(
      fileSystem
          .file('/project/android/app/src/main/AndroidManifest.xml')
          .readAsStringSync(),
      afterFirstPatch,
    );
    expect(logger.infos, anyElement(contains('[dry-run]')));
  });
}
