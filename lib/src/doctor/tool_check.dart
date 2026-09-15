import 'package:process/process.dart';

enum CheckStatus { ok, missing, erroredButPresent }

class CheckResult {
  const CheckResult({required this.status, this.version, this.detail});

  final CheckStatus status;
  final String? version;
  final String? detail;
}

abstract class ToolCheck {
  const ToolCheck();

  String get name;

  /// Whether [CheckStatus.missing] should fail `flupo doctor` outright
  /// (git/dart/flutter) or only warn (adb — not every task needs it).
  bool get required;

  Future<CheckResult> check(ProcessManager processManager);
}
