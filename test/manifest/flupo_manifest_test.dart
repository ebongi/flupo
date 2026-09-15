import 'package:file/memory.dart';
import 'package:flupo/src/manifest/flupo_manifest.dart';
import 'package:test/test.dart';

void main() {
  group('FlupoManifest.parse', () {
    test('parses a minimal valid manifest with build defaults', () {
      final manifest = FlupoManifest.parse('''
name: my_app
version: 1.0.0+1
identifier: com.example.myapp
''');

      expect(manifest.name, 'my_app');
      expect(manifest.version, '1.0.0+1');
      expect(manifest.identifier, 'com.example.myapp');
      expect(manifest.permissions, isEmpty);
      expect(manifest.build.target, 'apk');
      expect(manifest.build.runner, 'github_actions');
    });

    test('parses declared permissions and build config', () {
      final manifest = FlupoManifest.parse('''
name: my_app
version: 1.0.0+1
identifier: com.example.myapp
permissions:
  camera: "Need camera access for profile photo"
  location: "Need location for delivery tracking"
build:
  target: appbundle
  runner: github_actions
''');

      expect(manifest.permissions, {
        'camera': 'Need camera access for profile photo',
        'location': 'Need location for delivery tracking',
      });
      expect(manifest.build.target, 'appbundle');
    });

    test('parses build.github.repo and workflow', () {
      final manifest = FlupoManifest.parse('''
name: my_app
version: 1.0.0+1
identifier: com.example.myapp
build:
  target: apk
  runner: github_actions
  github:
    repo: acme/my_app
    workflow: build.yml
''');

      expect(manifest.build.githubRepo, 'acme/my_app');
      expect(manifest.build.githubWorkflow, 'build.yml');
    });

    test('rejects a build.github.repo not shaped like "owner/name"', () {
      expect(
        () => FlupoManifest.parse('''
name: my_app
version: 1.0.0+1
identifier: com.example.myapp
build:
  target: apk
  runner: github_actions
  github:
    repo: not-a-valid-repo
'''),
        throwsA(
          isA<ManifestValidationException>().having(
            (e) => e.errors.single,
            'errors',
            contains('must look like "owner/name"'),
          ),
        ),
      );
    });

    test('rejects an empty build.github.workflow', () {
      expect(
        () => FlupoManifest.parse('''
name: my_app
version: 1.0.0+1
identifier: com.example.myapp
build:
  target: apk
  runner: github_actions
  github:
    repo: acme/my_app
    workflow: ""
'''),
        throwsA(
          isA<ManifestValidationException>().having(
            (e) => e.errors.single,
            'errors',
            contains('"build.github.workflow" must be a non-empty string'),
          ),
        ),
      );
    });

    test('collects every validation error in one pass', () {
      try {
        FlupoManifest.parse('''
name: ""
version: ""
identifier: "not-reverse-dns"
permissions:
  xray: "scan for hidden robots"
build:
  target: exe
  runner: jenkins
''');
        fail('expected ManifestValidationException');
      } on ManifestValidationException catch (e) {
        expect(e.errors, hasLength(6));
        expect(e.errors.join('\n'), contains('"name" is required'));
        expect(e.errors.join('\n'), contains('"version" is required'));
        expect(e.errors.join('\n'), contains('reverse-DNS style'));
        expect(e.errors.join('\n'), contains('Unknown permission "xray"'));
        expect(e.errors.join('\n'), contains('Unsupported build target "exe"'));
        expect(
          e.errors.join('\n'),
          contains('Unsupported build runner "jenkins"'),
        );
      }
    });

    test('rejects a permission with a non-string description', () {
      expect(
        () => FlupoManifest.parse('''
name: my_app
version: 1.0.0+1
identifier: com.example.myapp
permissions:
  camera: 42
'''),
        throwsA(
          isA<ManifestValidationException>().having(
            (e) => e.errors.single,
            'errors',
            contains('needs a non-empty description string'),
          ),
        ),
      );
    });

    test('rejects malformed YAML', () {
      expect(
        () => FlupoManifest.parse('not: [valid: yaml'),
        throwsA(isA<ManifestValidationException>()),
      );
    });

    test('rejects a top-level YAML value that is not a mapping', () {
      expect(
        () => FlupoManifest.parse('- just\n- a\n- list\n'),
        throwsA(
          isA<ManifestValidationException>().having(
            (e) => e.errors.single,
            'errors',
            contains('must be a YAML mapping'),
          ),
        ),
      );
    });
  });

  group('FlupoManifest.fromFile', () {
    test('throws an actionable error when flupo.yaml is missing', () async {
      final fs = MemoryFileSystem();

      expect(
        () => FlupoManifest.fromFile(fs.file('/project/flupo.yaml')),
        throwsA(
          isA<ManifestValidationException>().having(
            (e) => e.errors.single,
            'errors',
            contains('Run `flupo init` first'),
          ),
        ),
      );
    });

    test('reads and parses an existing flupo.yaml', () async {
      final fs = MemoryFileSystem();
      final file = fs.file('/project/flupo.yaml')..createSync(recursive: true);
      await file.writeAsString('''
name: my_app
version: 1.0.0+1
identifier: com.example.myapp
''');

      final manifest = await FlupoManifest.fromFile(file);

      expect(manifest.name, 'my_app');
    });
  });
}
