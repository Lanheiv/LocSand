import 'package:flutter/material.dart';
import 'package:locsand/src/core_protocols.dart';
import 'package:locsand/view/home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await coreProtocols();
  } catch (e) {
    debugPrint("coreProtocols failed to start: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LocSand',
      home: const HomeScreen(),
    );
  }
}
