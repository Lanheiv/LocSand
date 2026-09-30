import 'dart:async';
import 'package:flutter/material.dart';

import 'package:locsand/src/core_protocols.dart';
import 'package:locsand/view/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
  unawaited(_startCore());
}

Future<void> _startCore() async {
  try {
    await coreProtocols();
  } catch (e) {
    debugPrint("coreProtocols failed: $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}
