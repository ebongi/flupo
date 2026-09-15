import 'package:flutter/material.dart';

import 'pairing_screen.dart';

void main() {
  runApp(const FlupoGoApp());
}

class FlupoGoApp extends StatelessWidget {
  const FlupoGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flupo Go',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const PairingScreen(),
    );
  }
}
