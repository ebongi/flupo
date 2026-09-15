import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:process/process.dart';

import 'util/logger.dart';

/// The `flupo` CLI's command tree. Every subcommand shares this instance's
/// injected [fileSystem], [processManager], and [logger] so tests can swap in
/// a `MemoryFileSystem` and a mocked `ProcessManager` without touching the
/// real machine.
class FlupoCommandRunner extends CommandRunner<int> {
  FlupoCommandRunner({
    FileSystem? fileSystem,
    ProcessManager? processManager,
    Logger? logger,
  }) : fileSystem = fileSystem ?? LocalFileSystem(),
       processManager = processManager ?? const LocalProcessManager(),
       logger = logger ?? const StandardLogger(),
       super('flupo', "A managed developer platform CLI for Flutter.") {
    // Subcommands (doctor, init, patch, build, start) register themselves
    // here as each is implemented.
  }

  final FileSystem fileSystem;
  final ProcessManager processManager;
  final Logger logger;

  /// Runs [arguments] and reduces every outcome (success, `--help`, or a
  /// [UsageException]) to a process exit code, so `bin/flupo.dart` never has
  /// to know about `package:args` exception types.
  Future<int> runFlupo(Iterable<String> arguments) async {
    try {
      final result = await run(arguments);
      return result ?? 0;
    } on UsageException catch (e) {
      logger.error('${e.message}\n\n${e.usage}');
      return 64;
    }
  }
}
