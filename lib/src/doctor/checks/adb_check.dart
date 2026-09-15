import 'dart:io';

import 'package:process/process.dart';

import '../tool_check.dart';

/// adb is only needed for on-device install/pairing flows, not every flupo
/// task, so it is never `required` — its absence is a warning, not a failure.
class AdbCheck extends ToolCheck {
  const AdbCheck();

  @override
  String get name => 'ADB';

  @override
  bool get required => false;

  static final RegExp _versionPattern = RegExp(r'version (\S+)');

  @override
  Future<CheckResult> check(ProcessManager processManager) async {
    try {
      final result = await processManager.run(['adb', 'version']);
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
