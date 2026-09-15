import 'package:file/file.dart';
import 'package:yaml/yaml.dart';

import 'permission_catalog.dart';

class BuildConfig {
  const BuildConfig({this.target = 'apk', this.runner = 'github_actions'});

  final String target;
  final String runner;

  static const List<String> supportedTargets = ['apk', 'appbundle', 'ipa'];
  static const List<String> supportedRunners = ['github_actions'];

  factory BuildConfig.fromYaml(YamlMap? yaml) {
    if (yaml == null) return const BuildConfig();
    return BuildConfig(
      target: yaml['target'] as String? ?? 'apk',
      runner: yaml['runner'] as String? ?? 'github_actions',
    );
  }
}

/// Thrown by [FlupoManifest.parse]/[FlupoManifest.fromFile] with every
/// problem found in one pass, so a single `flupo patch` run can report the
/// whole manifest's issues at once instead of one-at-a-time.
class ManifestValidationException implements Exception {
  ManifestValidationException(this.errors) : assert(errors.isNotEmpty);

  final List<String> errors;

  @override
  String toString() => errors.join('\n');
}

class FlupoManifest {
  const FlupoManifest({
    required this.name,
    required this.version,
    required this.identifier,
    this.permissions = const {},
    this.build = const BuildConfig(),
  });

  final String name;
  final String version;
  final String identifier;
  final Map<String, String> permissions;
  final BuildConfig build;

  static final RegExp _identifierPattern = RegExp(
    r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$',
  );

  static Future<FlupoManifest> fromFile(File file) async {
    if (!await file.exists()) {
      throw ManifestValidationException([
        'No flupo.yaml found at ${file.path}. Run `flupo init` first.',
      ]);
    }
    return FlupoManifest.parse(await file.readAsString());
  }

  factory FlupoManifest.parse(String yamlContent) {
    final errors = <String>[];

    final YamlMap doc;
    try {
      final loaded = loadYaml(yamlContent);
      if (loaded is! YamlMap) {
        throw ManifestValidationException([
          'flupo.yaml must be a YAML mapping at the top level.',
        ]);
      }
      doc = loaded;
    } on YamlException catch (e) {
      throw ManifestValidationException([
        'Could not parse flupo.yaml: ${e.message}',
      ]);
    }

    final rawName = doc['name'];
    if (rawName is! String || rawName.isEmpty) {
      errors.add('"name" is required and must be a non-empty string.');
    }

    final rawVersion = doc['version'];
    if (rawVersion is! String || rawVersion.isEmpty) {
      errors.add('"version" is required and must be a non-empty string.');
    }

    final rawIdentifier = doc['identifier'];
    if (rawIdentifier is! String || rawIdentifier.isEmpty) {
      errors.add('"identifier" is required and must be a non-empty string.');
    } else if (!_identifierPattern.hasMatch(rawIdentifier)) {
      errors.add(
        '"identifier" ("$rawIdentifier") must be a reverse-DNS style '
        'identifier, e.g. com.example.myapp.',
      );
    }

    final permissions = <String, String>{};
    final rawPermissions = doc['permissions'];
    if (rawPermissions != null) {
      if (rawPermissions is! YamlMap) {
        errors.add(
          '"permissions" must be a mapping of permission key to description.',
        );
      } else {
        for (final entry in rawPermissions.entries) {
          final key = entry.key.toString();
          if (!permissionCatalog.containsKey(key)) {
            errors.add(
              'Unknown permission "$key". Known permissions: '
              '${permissionCatalog.keys.join(', ')}.',
            );
            continue;
          }
          final value = entry.value;
          if (value is! String || value.isEmpty) {
            errors.add(
              'Permission "$key" needs a non-empty description string.',
            );
            continue;
          }
          permissions[key] = value;
        }
      }
    }

    var build = const BuildConfig();
    final rawBuild = doc['build'];
    if (rawBuild != null) {
      if (rawBuild is! YamlMap) {
        errors.add('"build" must be a mapping with "target" and "runner".');
      } else {
        build = BuildConfig.fromYaml(rawBuild);
        if (!BuildConfig.supportedTargets.contains(build.target)) {
          errors.add(
            'Unsupported build target "${build.target}". Supported: '
            '${BuildConfig.supportedTargets.join(', ')}.',
          );
        }
        if (!BuildConfig.supportedRunners.contains(build.runner)) {
          errors.add(
            'Unsupported build runner "${build.runner}". Supported: '
            '${BuildConfig.supportedRunners.join(', ')}.',
          );
        }
      }
    }

    if (errors.isNotEmpty) {
      throw ManifestValidationException(errors);
    }

    return FlupoManifest(
      name: rawName as String,
      version: rawVersion as String,
      identifier: rawIdentifier as String,
      permissions: permissions,
      build: build,
    );
  }
}
