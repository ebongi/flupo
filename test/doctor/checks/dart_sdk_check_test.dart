import 'dart:io';

import 'package:flupo/src/doctor/checks/dart_sdk_check.dart';
import 'package:flupo/src/doctor/tool_check.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/mocks.dart';

void main() {
  late MockProcessManager processManager;

  setUp(() => processManager = MockProcessManager());

  test('is required', () {
    expect(const DartSdkCheck().required, isTrue);
  });

  test('reports ok using stdout, matching this SDK\'s real output', () async {
    when(() => processManager.run(any())).thenAnswer(
      (_) async => ProcessResult(
        0,
        0,
        'Dart SDK version: 3.12.2 (stable) (Tue Jun 9 01:11:39 2026 -0700) on "linux_x64"',
        '',
      ),
    );

    final result = await const DartSdkCheck().check(processManager);

    expect(result.status, CheckStatus.ok);
    expect(result.version, '3.12.2');
    verify(
      () => processManager.run(any(that: equals(['dart', '--version']))),
    ).called(1);
  });

  test('reports missing when dart is not on PATH', () async {
    when(
      () => processManager.run(any()),
    ).thenThrow(const ProcessException('dart', ['--version']));

    final result = await const DartSdkCheck().check(processManager);

    expect(result.status, CheckStatus.missing);
  });
}
