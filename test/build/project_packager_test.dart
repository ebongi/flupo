import 'package:archive/archive.dart';
import 'package:file/memory.dart';
import 'package:flupo/src/build/project_packager.dart';
import 'package:test/test.dart';

void main() {
  test('includes project files and excludes default-ignored directories', () {
    final fs = MemoryFileSystem();
    fs.file('/project/lib/main.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}');
    fs.file('/project/pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: project');
    fs.file('/project/.git/HEAD')
      ..createSync(recursive: true)
      ..writeAsStringSync('ref: refs/heads/main');
    fs.file('/project/.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{}');
    fs.file('/project/build/app/outputs/app.apk')
      ..createSync(recursive: true)
      ..writeAsStringSync('binary');
    fs.file('/project/ios/Pods/manifest.lock')
      ..createSync(recursive: true)
      ..writeAsStringSync('pods');
    fs.file('/project/android/.gradle/cache.bin')
      ..createSync(recursive: true)
      ..writeAsStringSync('gradle cache');

    final zipBytes = packageProject(fs.directory('/project'));
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final names = archive.files.map((f) => f.name).toSet();

    expect(names, contains('lib/main.dart'));
    expect(names, contains('pubspec.yaml'));
    expect(names, isNot(contains('.git/HEAD')));
    expect(names, isNot(contains('.dart_tool/package_config.json')));
    expect(names, isNot(contains('build/app/outputs/app.apk')));
    expect(names, isNot(contains('ios/Pods/manifest.lock')));
    expect(names, isNot(contains('android/.gradle/cache.bin')));
  });

  test('does not exclude a directory that merely shares a name prefix', () {
    final fs = MemoryFileSystem();
    // "build_notes.txt" must survive even though "build" is excluded.
    fs.file('/project/build_notes.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync('not the build output directory');

    final zipBytes = packageProject(fs.directory('/project'));
    final archive = ZipDecoder().decodeBytes(zipBytes);

    expect(archive.files.map((f) => f.name), contains('build_notes.txt'));
  });
}
