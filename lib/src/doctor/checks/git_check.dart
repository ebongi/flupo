import 'dart:io';

import 'package:process/process.dart';

import '../tool_check.dart';

class GitCheck extends ToolCheck {
  const GitCheck();

  @override
  String get name => 'Git';

  @override
  bool get required => true;

  static final RegExp _versionPattern = RegExp(r'(\d+\.\d+(?:\.\d+)?)');

  @override
  Future<CheckResult> check(ProcessManager processManager) async {
    try {
      final result = await processManager.run(['git', '--version']);
      if (result.exitCode != 0) {
        return CheckResult(
          status: CheckStatus.erroredButPresent,
          detail: result.stderr.toString().trim(),
        );
      }
      final output = result.stdout.toString().trim();
      final match = _versionPattern.firstMatch(output);
      return CheckResult(
        status: CheckStatus.ok,
        version: match?.group(1) ?? output,
      );
    } on ProcessException {
      return const CheckResult(status: CheckStatus.missing);
    }
  }
}
