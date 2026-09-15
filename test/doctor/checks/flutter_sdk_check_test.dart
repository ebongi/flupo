import 'dart:convert';
import 'dart:io';

import 'package:flupo/src/doctor/checks/flutter_sdk_check.dart';
import 'package:flupo/src/doctor/tool_check.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/mocks.dart';

void main() {
  late MockProcessManager processManager;

  setUp(() => processManager = MockProcessManager());

  test('is required', () {
    expect(const FlutterSdkCheck().required, isTrue);
  });

  test('parses frameworkVersion and channel from --machine JSON', () async {
    when(() => processManager.run(any())).thenAnswer(
      (_) async => ProcessResult(
        0,
        0,
        jsonEncode({'frameworkVersion': '3.44.9', 'channel': 'stable'}),
        '',
      ),
    );

    final result = await const FlutterSdkCheck().check(processManager);

    expect(result.status, CheckStatus.ok);
    expect(result.version, '3.44.9 (stable)');
    verify(
      () => processManager.run(
        any(that: equals(['flutter', '--version', '--machine'])),
      ),
    ).called(1);
  });

  test('reports missing when flutter is not on PATH', () async {
    when(
      () => processManager.run(any()),
    ).thenThrow(const ProcessException('flutter', ['--version', '--machine']));

    final result = await const FlutterSdkCheck().check(processManager);

    expect(result.status, CheckStatus.missing);
  });

  test('reports erroredButPresent on unparsable output', () async {
    when(
      () => processManager.run(any()),
    ).thenAnswer((_) async => ProcessResult(0, 0, 'not json', ''));

    final result = await const FlutterSdkCheck().check(processManager);

    expect(result.status, CheckStatus.erroredButPresent);
  });
}
