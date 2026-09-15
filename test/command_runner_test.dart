import 'package:file/memory.dart';
import 'package:flupo/src/command_runner.dart';
import 'package:test/test.dart';

void main() {
  group('FlupoCommandRunner', () {
    test('exposes the expected executable name and description', () {
      final runner = FlupoCommandRunner(fileSystem: MemoryFileSystem());

      expect(runner.executableName, 'flupo');
      expect(runner.description, isNotEmpty);
    });

    test('--help exits 0 without throwing', () async {
      final runner = FlupoCommandRunner(fileSystem: MemoryFileSystem());

      final code = await runner.runFlupo(['--help']);

      expect(code, 0);
    });

    test('an unknown command is reported as a usage error (exit 64)', () async {
      final runner = FlupoCommandRunner(fileSystem: MemoryFileSystem());

      final code = await runner.runFlupo(['not-a-real-command']);

      expect(code, 64);
    });
  });
}
