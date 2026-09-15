import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flupo_go/pairing_screen.dart';

const _mobileScannerMethodChannel = MethodChannel(
  'dev.steenbakker.mobile_scanner/scanner/method',
);

Future<HttpServer> _startFakePairingServer({
  required String expectedToken,
  List<Map<String, dynamic>> extraMessagesAfterPairing = const [],
  void Function(String data)? onMessageAfterPairing,
  void Function()? onDisconnect,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    var paired = false;
    socket.listen(
      (data) {
        if (!paired) {
          if (data == expectedToken) {
            paired = true;
            socket.add(jsonEncode({'type': 'paired'}));
            for (final message in extraMessagesAfterPairing) {
              socket.add(jsonEncode(message));
            }
          }
          return;
        }
        onMessageAfterPairing?.call(data as String);
      },
      onDone: onDisconnect,
    );
  });
  return server;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // MobileScanner's camera lifecycle (start/stop/dispose) goes through this
    // platform channel, which has no real implementation in a widget test —
    // stub it out so mounting/unmounting the scanner doesn't throw.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _mobileScannerMethodChannel,
          (call) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_mobileScannerMethodChannel, null);
  });

  testWidgets('shows an error for an invalid QR payload', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PairingScreen(useCameraPreview: false)),
    );

    final state = tester.state<PairingScreenState>(find.byType(PairingScreen));
    state.handleScannedData('not valid json');
    await tester.pump();

    expect(
      find.text('That QR code is not a valid flupo pairing code.'),
      findsOneWidget,
    );
  });

  testWidgets('pairs and shows relayed status after a valid scan', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PairingScreen(useCameraPreview: false)),
    );
    final state = tester.state<PairingScreenState>(find.byType(PairingScreen));

    // The whole real socket round-trip — starting the fake server, scanning,
    // and connecting — has to happen inside runAsync: outside it, Flutter's
    // test binding never services real dart:io I/O callbacks, so the fake
    // server would never see the incoming connection at all.
    late HttpServer server;
    await tester.runAsync(() async {
      server = await _startFakePairingServer(
        expectedToken: 'test-token',
        extraMessagesAfterPairing: [
          {'type': 'status', 'message': 'app.start'},
        ],
      );
      final payload = jsonEncode({
        'host': 'localhost',
        'port': server.port,
        'projectName': 'flupo_go',
        'token': 'test-token',
      });
      state.handleScannedData(payload);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    addTearDown(server.close);
    await tester.pump();

    expect(find.text('Paired to flupo_go'), findsOneWidget);
    expect(find.text('app.start'), findsOneWidget);
  });

  testWidgets('tapping Reload sends a reload message to the server', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PairingScreen(useCameraPreview: false)),
    );
    final state = tester.state<PairingScreenState>(find.byType(PairingScreen));

    late HttpServer server;
    final receivedAfterPairing = <String>[];
    await tester.runAsync(() async {
      server = await _startFakePairingServer(
        expectedToken: 'test-token',
        onMessageAfterPairing: receivedAfterPairing.add,
      );
      final payload = jsonEncode({
        'host': 'localhost',
        'port': server.port,
        'projectName': 'flupo_go',
        'token': 'test-token',
      });
      state.handleScannedData(payload);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    addTearDown(server.close);
    await tester.pump();

    expect(find.widgetWithText(ElevatedButton, 'Reload'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Reload'));
    await tester.pump();
    // Give the real socket write time to actually reach the server.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );

    expect(receivedAfterPairing, [
      jsonEncode({'type': 'reload'}),
    ]);
  });

  testWidgets('Go home from a paired session closes the socket and rescans', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PairingScreen(useCameraPreview: false)),
    );
    final state = tester.state<PairingScreenState>(find.byType(PairingScreen));

    late HttpServer server;
    var serverSawDisconnect = false;
    await tester.runAsync(() async {
      server = await _startFakePairingServer(
        expectedToken: 'test-token',
        onDisconnect: () => serverSawDisconnect = true,
      );
      final payload = jsonEncode({
        'host': 'localhost',
        'port': server.port,
        'projectName': 'flupo_go',
        'token': 'test-token',
      });
      state.handleScannedData(payload);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    addTearDown(server.close);
    await tester.pump();

    expect(find.text('Paired to flupo_go'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Go home'));
    await tester.pump();

    expect(
      find.text('Point your camera at a flupo start QR code'),
      findsOneWidget,
    );

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    expect(serverSawDisconnect, isTrue);
  });

  testWidgets('Try again from the error screen returns to scanning', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PairingScreen(useCameraPreview: false)),
    );
    final state = tester.state<PairingScreenState>(find.byType(PairingScreen));

    state.handleScannedData('not valid json');
    await tester.pump();
    expect(
      find.text('That QR code is not a valid flupo pairing code.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Try again'));
    await tester.pump();

    expect(
      find.text('Point your camera at a flupo start QR code'),
      findsOneWidget,
    );
  });
}
