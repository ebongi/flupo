import 'package:flupo/src/util/logger.dart';

class RecordingLogger implements Logger {
  final List<String> infos = [];
  final List<String> warnings = [];
  final List<String> errors = [];

  @override
  void info(String message) => infos.add(message);

  @override
  void warn(String message) => warnings.add(message);

  @override
  void error(String message) => errors.add(message);
}
