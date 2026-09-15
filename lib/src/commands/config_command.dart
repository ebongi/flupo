import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:yaml/yaml.dart' show CollectionStyle;
import 'package:yaml_edit/yaml_edit.dart';

import '../manifest/flupo_manifest.dart';
import '../manifest/permission_catalog.dart';
import '../util/logger.dart';

const List<String> _scalarConfigKeys = [
  'name',
  'version',
  'identifier',
  'build.target',
  'build.runner',
  'build.github.repo',
  'build.github.workflow',
];

bool _isKnownKey(String key) {
  if (_scalarConfigKeys.contains(key)) return true;
  if (key.startsWith('permissions.')) {
    return permissionCatalog.containsKey(key.substring('permissions.'.length));
  }
  return false;
}

String _unknownKeyMessage(String key) =>
    'Unknown config key "$key". Known keys: ${_scalarConfigKeys.join(', ')}, '
    'permissions.<${permissionCatalog.keys.join('|')}>.';

bool _pathExists(YamlEditor editor, List<String> path) {
  try {
    editor.parseAt(path);
    return true;
  } on ArgumentError {
    return false;
  }
}

/// `YamlEditor.update` requires every ancestor of a path to already exist as
/// a map. When some don't (e.g. setting `build.github.repo` on a manifest
/// that predates the `github:` section), this builds the whole missing tail
/// as one nested map literal and sets it in a single `update` call — an
/// empty map has no valid block-style representation (`{}` either way), so
/// creating it empty first and filling it in afterwards would permanently
/// lock that section into flow style. Building it complete in one call lets
/// block style actually take effect, reading like the rest of a
/// hand-written flupo.yaml instead of `github: {repo: ...}`.
void _setValue(YamlEditor editor, List<String> segments, String value) {
  var existingDepth = 0;
  for (var i = 1; i < segments.length; i++) {
    if (!_pathExists(editor, segments.sublist(0, i))) break;
    existingDepth = i;
  }

  if (existingDepth == segments.length - 1) {
    editor.update(segments, value);
    return;
  }

  Object nested = value;
  for (var i = segments.length - 1; i > existingDepth; i--) {
    nested = {segments[i]: nested};
  }
  editor.update(
    segments.sublist(0, existingDepth + 1),
    wrapAsYamlNode(nested, collectionStyle: CollectionStyle.BLOCK),
  );
}

/// Parent for `flupo config get/set/unset` — reads and writes individual
/// flupo.yaml fields via package:yaml_edit, which preserves comments and
/// formatting everywhere else in the file, unlike FlupoManifest's own
/// parse-only model or a full rewrite.
class ConfigCommand extends Command<int> {
  ConfigCommand({required this.fileSystem, required this.logger}) {
    addSubcommand(_ConfigGetCommand(fileSystem: fileSystem, logger: logger));
    addSubcommand(_ConfigSetCommand(fileSystem: fileSystem, logger: logger));
    addSubcommand(_ConfigUnsetCommand(fileSystem: fileSystem, logger: logger));
  }

  final FileSystem fileSystem;
  final Logger logger;

  @override
  String get name => 'config';

  @override
  String get description => 'Reads and writes individual flupo.yaml fields.';
}

abstract class _ConfigSubcommand extends Command<int> {
  _ConfigSubcommand({required this.fileSystem, required this.logger}) {
    argParser.addOption(
      'path',
      help:
          'The Flutter project root whose flupo.yaml to use (defaults to '
          'the current directory).',
    );
  }

  final FileSystem fileSystem;
  final Logger logger;

  File manifestFile() {
    final rawPath = argResults!.option('path');
    final projectDir = rawPath == null
        ? fileSystem.currentDirectory
        : fileSystem.directory(
            fileSystem.path.normalize(fileSystem.path.absolute(rawPath)),
          );
    return projectDir.childFile('flupo.yaml');
  }

  Future<bool> reportIfManifestMissing(File file) async {
    if (await file.exists()) return false;
    logger.error(
      'No flupo.yaml found at ${file.path}. Run `flupo init` first.',
    );
    return true;
  }
}

class _ConfigGetCommand extends _ConfigSubcommand {
  _ConfigGetCommand({required super.fileSystem, required super.logger});

  @override
  String get name => 'get';

  @override
  String get description =>
      'Prints the current value of a flupo.yaml key, e.g. build.target.';

  @override
  String get invocation => 'flupo config get <key>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException(
        'Expected exactly one key, e.g. `flupo config get build.target`.',
      );
    }
    final key = rest.single;

    final file = manifestFile();
    if (await reportIfManifestMissing(file)) return 1;

    final editor = YamlEditor(await file.readAsString());
    final node = editor.parseAt(
      key.split('.'),
      orElse: () => wrapAsYamlNode(null),
    );
    if (node.value == null) {
      logger.info('$key is not set.');
    } else {
      logger.info(node.value.toString());
    }
    return 0;
  }
}

class _ConfigSetCommand extends _ConfigSubcommand {
  _ConfigSetCommand({required super.fileSystem, required super.logger});

  @override
  String get name => 'set';

  @override
  String get description =>
      'Sets a flupo.yaml key to a value, e.g. `build.target apk`.';

  @override
  String get invocation => 'flupo config set <key> <value>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 2) {
      usageException(
        'Expected a key and a value, e.g. `flupo config set build.target apk`.',
      );
    }
    final key = rest[0];
    final value = rest[1];

    if (!_isKnownKey(key)) {
      logger.error(_unknownKeyMessage(key));
      return 1;
    }

    final file = manifestFile();
    if (await reportIfManifestMissing(file)) return 1;

    final editor = YamlEditor(await file.readAsString());
    _setValue(editor, key.split('.'), value);

    final updated = editor.toString();
    try {
      FlupoManifest.parse(updated);
    } on ManifestValidationException catch (e) {
      logger.error('That value would make flupo.yaml invalid:\n$e');
      return 1;
    }

    await file.writeAsString(updated);
    logger.info('Set $key = $value in ${file.path}.');
    return 0;
  }
}

class _ConfigUnsetCommand extends _ConfigSubcommand {
  _ConfigUnsetCommand({required super.fileSystem, required super.logger});

  @override
  String get name => 'unset';

  @override
  String get description => 'Removes a flupo.yaml key.';

  @override
  String get invocation => 'flupo config unset <key>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException(
        'Expected exactly one key, e.g. `flupo config unset permissions.camera`.',
      );
    }
    final key = rest.single;

    if (!_isKnownKey(key)) {
      logger.error(_unknownKeyMessage(key));
      return 1;
    }

    final file = manifestFile();
    if (await reportIfManifestMissing(file)) return 1;

    final editor = YamlEditor(await file.readAsString());
    final segments = key.split('.');
    if (!_pathExists(editor, segments)) {
      logger.info('$key is already not set.');
      return 0;
    }
    editor.remove(segments);

    final updated = editor.toString();
    try {
      FlupoManifest.parse(updated);
    } on ManifestValidationException catch (e) {
      logger.error('Removing $key would make flupo.yaml invalid:\n$e');
      return 1;
    }

    await file.writeAsString(updated);
    logger.info('Removed $key from ${file.path}.');
    return 0;
  }
}
