import 'package:flutter/material.dart';
import 'package:locsand/src/core_protocols.dart';
import 'package:locsand/pages/home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await coreProtocols();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Home page',
      home: const HomeScreen(),
    );
  }
}