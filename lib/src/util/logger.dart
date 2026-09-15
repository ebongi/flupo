import 'dart:io';

/// Injectable output sink so commands never call `print`/`stdout` directly,
/// letting tests capture output without touching the real console.
abstract class Logger {
  void info(String message);
  void warn(String message);
  void error(String message);
}

class StandardLogger implements Logger {
  const StandardLogger();

  @override
  void info(String message) => stdout.writeln(message);

  @override
  void warn(String message) => stdout.writeln('[WARN] $message');

  @override
  void error(String message) => stderr.writeln(message);
}
