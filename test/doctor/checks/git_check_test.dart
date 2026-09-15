import 'dart:io';

import 'package:flupo/src/doctor/checks/git_check.dart';
import 'package:flupo/src/doctor/tool_check.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/mocks.dart';

void main() {
  late MockProcessManager processManager;

  setUp(() => processManager = MockProcessManager());

  test('is required', () {
    expect(const GitCheck().required, isTrue);
  });

  test('reports ok with the parsed version when git is present', () async {
    when(
      () => processManager.run(any()),
    ).thenAnswer((_) async => ProcessResult(0, 0, 'git version 2.43.0\n', ''));

    final result = await const GitCheck().check(processManager);

    expect(result.status, CheckStatus.ok);
    expect(result.version, '2.43.0');
    verify(
      () => processManager.run(any(that: equals(['git', '--version']))),
    ).called(1);
  });

  test('reports missing when git is not on PATH', () async {
    when(
      () => processManager.run(any()),
    ).thenThrow(const ProcessException('git', ['--version']));

    final result = await const GitCheck().check(processManager);

    expect(result.status, CheckStatus.missing);
  });

  test('reports erroredButPresent when git exits non-zero', () async {
    when(
      () => processManager.run(any()),
    ).thenAnswer((_) async => ProcessResult(0, 1, '', 'boom'));

    final result = await const GitCheck().check(processManager);

    expect(result.status, CheckStatus.erroredButPresent);
    expect(result.detail, 'boom');
  });
}
