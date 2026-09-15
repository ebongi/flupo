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
  required List<Map<String, dynamic>> extraMessagesAfterPairing,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen((data) {
      if (data == expectedToken) {
        socket.add(jsonEncode({'type': 'paired'}));
        for (final message in extraMessagesAfterPairing) {
          socket.add(jsonEncode(message));
        }
      }
    });
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
}
