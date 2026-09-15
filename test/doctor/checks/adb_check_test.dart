import 'dart:io';

import 'package:flupo/src/doctor/checks/adb_check.dart';
import 'package:flupo/src/doctor/tool_check.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/mocks.dart';

void main() {
  late MockProcessManager processManager;

  setUp(() => processManager = MockProcessManager());

  test('is not required', () {
    expect(const AdbCheck().required, isFalse);
  });

  test('reports ok with the parsed version when adb is present', () async {
    when(() => processManager.run(any())).thenAnswer(
      (_) async => ProcessResult(
        0,
        0,
        'Android Debug Bridge version 1.0.41\nVersion 34.0.5-debian',
        '',
      ),
    );

    final result = await const AdbCheck().check(processManager);

    expect(result.status, CheckStatus.ok);
    expect(result.version, '1.0.41');
    verify(
      () => processManager.run(any(that: equals(['adb', 'version']))),
    ).called(1);
  });

  test('reports missing (not required) when adb is not on PATH', () async {
    when(
      () => processManager.run(any()),
    ).thenThrow(const ProcessException('adb', ['version']));

    final result = await const AdbCheck().check(processManager);

    expect(result.status, CheckStatus.missing);
  });
}
