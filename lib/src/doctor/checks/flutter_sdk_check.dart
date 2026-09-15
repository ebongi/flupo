import 'dart:convert';
import 'dart:io';

import 'package:process/process.dart';

import '../tool_check.dart';

class FlutterSdkCheck extends ToolCheck {
  const FlutterSdkCheck();

  @override
  String get name => 'Flutter SDK';

  @override
  bool get required => true;

  @override
  Future<CheckResult> check(ProcessManager processManager) async {
    try {
      final result = await processManager.run([
        'flutter',
        '--version',
        '--machine',
      ]);
      if (result.exitCode != 0) {
        return CheckResult(
          status: CheckStatus.erroredButPresent,
          detail: result.stderr.toString().trim(),
        );
      }
      final json = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
      final frameworkVersion = json['frameworkVersion'] as String?;
      final channel = json['channel'] as String?;
      final version = [
        ?frameworkVersion,
        if (channel != null) '($channel)',
      ].join(' ');
      return CheckResult(
        status: CheckStatus.ok,
        version: version.isEmpty ? null : version,
      );
    } on ProcessException {
      return const CheckResult(status: CheckStatus.missing);
    } on FormatException catch (e) {
      return CheckResult(
        status: CheckStatus.erroredButPresent,
        detail:
            'Could not parse `flutter --version --machine` output: ${e.message}',
      );
    }
  }
}
