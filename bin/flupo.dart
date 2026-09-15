import 'dart:io';

import 'package:flupo/src/command_runner.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await FlupoCommandRunner().runFlupo(arguments);
}
