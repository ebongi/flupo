import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:process/process.dart';

import '../doctor/checks/adb_check.dart';
import '../doctor/checks/dart_sdk_check.dart';
import '../doctor/checks/flutter_sdk_check.dart';
import '../doctor/checks/git_check.dart';
import '../doctor/tool_check.dart';
import '../util/logger.dart';

class DoctorCommand extends Command<int> {
  DoctorCommand({required this.processManager, required this.logger}) {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print results as JSON instead of a table.',
    );
  }

  final ProcessManager processManager;
  final Logger logger;

  static const List<ToolCheck> _checks = [
    GitCheck(),
    DartSdkCheck(),
    FlutterSdkCheck(),
    AdbCheck(),
  ];

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Checks this machine for the tools flupo needs (git, dart, flutter, adb).';

  @override
  Future<int> run() async {
    final results = await Future.wait(
      _checks.map((check) => check.check(processManager)),
    );

    if (argResults!.flag('json')) {
      _printJson(results);
    } else {
      _printTable(results);
    }

    final missingRequired = [
      for (var i = 0; i < _checks.length; i++)
        if (_checks[i].required && results[i].status != CheckStatus.ok)
          _checks[i].name,
    ];

    return missingRequired.isEmpty ? 0 : 1;
  }

  void _printJson(List<CheckResult> results) {
    final payload = {
      for (var i = 0; i < _checks.length; i++)
        _checks[i].name: {
          'status': results[i].status.name,
          'required': _checks[i].required,
          if (results[i].version != null) 'version': results[i].version,
          if (results[i].detail != null) 'detail': results[i].detail,
        },
    };
    logger.info(const JsonEncoder.withIndent('  ').convert(payload));
  }

  void _printTable(List<CheckResult> results) {
    final nameWidth = _checks
        .map((check) => check.name.length)
        .reduce((a, b) => a > b ? a : b);

    for (var i = 0; i < _checks.length; i++) {
      final check = _checks[i];
      final result = results[i];
      final label = _label(check, result);
      final detail = result.version ?? result.detail ?? '';
      logger.info(
        '$label ${check.name.padRight(nameWidth)}  $detail'.trimRight(),
      );
    }
  }

  String _label(ToolCheck check, CheckResult result) {
    if (result.status == CheckStatus.ok) return '[OK]     ';
    if (!check.required) return '[WARN]   ';
    return switch (result.status) {
      CheckStatus.missing => '[MISSING]',
      CheckStatus.erroredButPresent => '[ERROR]  ',
      CheckStatus.ok => '[OK]     ',
    };
  }
}
