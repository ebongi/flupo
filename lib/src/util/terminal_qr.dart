import 'package:ascii_qr/ascii_qr.dart';

/// Renders [data] as a scannable QR code made of terminal characters.
String renderTerminalQr(String data) => AsciiQrGenerator.generate(data);
