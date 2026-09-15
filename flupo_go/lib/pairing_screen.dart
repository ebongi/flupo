import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'pairing_payload.dart';

typedef WebSocketConnector = WebSocketChannel Function(Uri uri);

enum PairingStatus { scanning, connecting, paired, error }

/// The Flupo Go home screen: scans a `flupo start` QR code, opens its
/// pairing WebSocket, and shows whatever status text the dev session
/// relays. MVP scope only — no bytecode is received or executed here, just
/// status/log text and (later) a way to request a reload.
class PairingScreen extends StatefulWidget {
  const PairingScreen({
    super.key,
    WebSocketConnector? connector,
    this.useCameraPreview = true,
  }) : connector = connector ?? WebSocketChannel.connect;

  final WebSocketConnector connector;

  /// False in tests: mounting the real camera preview pulls in several
  /// platform channels (orientation, barcode stream, ...) that don't exist
  /// in a widget-test sandbox. Tests call [PairingScreenState.handleScannedData]
  /// directly instead, so the preview itself is never exercised there.
  final bool useCameraPreview;

  @override
  State<PairingScreen> createState() => PairingScreenState();
}

class PairingScreenState extends State<PairingScreen> {
  final MobileScannerController _scannerController = MobileScannerController();

  PairingStatus _status = PairingStatus.scanning;
  String? _projectName;
  String? _statusMessage;
  String? _errorMessage;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;

  @override
  void dispose() {
    // Cancel before closing: closing the sink can synchronously deliver a
    // "done" event to a still-attached listener, which would call setState
    // on an element that's already mid-unmount.
    _channelSubscription?.cancel();
    _scannerController.dispose();
    _channel?.sink.close();
    super.dispose();
  }

  /// Handles one barcode detection from [MobileScanner]. Public, and split
  /// from [handleScannedData], so a test can inject a fake detection without
  /// needing real camera hardware.
  void handleDetection(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;
    handleScannedData(raw);
  }

  void handleScannedData(String data) {
    if (_status != PairingStatus.scanning) return;

    final PairingPayload payload;
    try {
      payload = PairingPayload.decode(data);
    } catch (_) {
      setState(() {
        _status = PairingStatus.error;
        _errorMessage = 'That QR code is not a valid flupo pairing code.';
      });
      return;
    }

    setState(() {
      _status = PairingStatus.connecting;
      _projectName = payload.projectName;
    });

    final channel = widget.connector(payload.wsUri);
    _channel = channel;
    channel.sink.add(payload.token);
    _channelSubscription = channel.stream.listen(
      (event) => _handleServerMessage(event as String),
      onError: (Object error) => _fail('Connection lost: $error'),
      onDone: () => _fail('Connection closed.'),
    );
  }

  void _handleServerMessage(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (decoded['type'] == 'paired') {
      setState(() => _status = PairingStatus.paired);
    } else if (decoded['type'] == 'status') {
      setState(() => _statusMessage = decoded['message'] as String?);
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _status = PairingStatus.error;
      _errorMessage = message;
    });
  }

  void _reset() {
    setState(() {
      _status = PairingStatus.scanning;
      _errorMessage = null;
      _projectName = null;
      _statusMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flupo Go')),
      body: switch (_status) {
        PairingStatus.scanning =>
          widget.useCameraPreview
              ? MobileScanner(
                  controller: _scannerController,
                  onDetect: handleDetection,
                )
              : const Center(
                  child: Text('Point your camera at a flupo start QR code'),
                ),
        PairingStatus.connecting => const Center(
          child: CircularProgressIndicator(),
        ),
        PairingStatus.paired => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Paired to $_projectName'),
              const SizedBox(height: 8),
              Text(_statusMessage ?? 'Waiting for hot reload...'),
            ],
          ),
        ),
        PairingStatus.error => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage ?? 'Something went wrong.'),
              TextButton(onPressed: _reset, child: const Text('Try again')),
            ],
          ),
        ),
      },
    );
  }
}
