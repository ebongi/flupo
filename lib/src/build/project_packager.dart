import 'package:archive/archive.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;

/// Directories excluded from the project archive: VCS metadata, build
/// caches, and native tooling output that a remote build regenerates itself.
const List<String> defaultPackagingExcludes = [
  '.git',
  '.dart_tool',
  'build',
  'ios/Pods',
  'android/.gradle',
];

/// Zips [projectDir] for `flupo build`'s `--upload-mode=artifact-zip` path.
///
/// Not wired up to any backend yet: GitHub's `workflow_dispatch` API only
/// accepts small string inputs, so it can't carry a zipped codebase — the
/// default build trigger is git-ref-based instead. This exists for a future
/// upload-based backend (or runner) that can actually accept a binary
/// payload.
List<int> packageProject(
  Directory projectDir, {
  List<String> excludes = defaultPackagingExcludes,
}) {
  final path = projectDir.fileSystem.path;
  final archive = Archive();

  for (final entity in projectDir.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final relativePath = path.relative(entity.path, from: projectDir.path);
    if (_isExcluded(relativePath, excludes, path)) continue;
    final bytes = entity.readAsBytesSync();
    archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
  }

  return ZipEncoder().encode(archive);
}

bool _isExcluded(String relativePath, List<String> excludes, p.Context path) {
  final segments = path.split(relativePath);
  for (final exclude in excludes) {
    final excludeSegments = path.split(exclude);
    if (segments.length < excludeSegments.length) continue;
    if (_startsWithSegments(segments, excludeSegments)) return true;
  }
  return false;
}

bool _startsWithSegments(List<String> segments, List<String> prefix) {
  for (var i = 0; i < prefix.length; i++) {
    if (segments[i] != prefix[i]) return false;
  }
  return true;
}
