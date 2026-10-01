import 'dart:async';
import 'package:flutter/material.dart';

import 'package:locsand/src/core_protocols.dart';
import 'package:locsand/src/helpers/theme_mode.dart';
import 'package:locsand/view/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadThemeMode();
  runApp(const MyApp());
  unawaited(_startCore());
}

Future<void> _startCore() async {
  try {
    await coreProtocols();
  } catch (e) {
    debugPrint('coreProtocols failed: $e');
  }
}

ThemeData _theme(Brightness brightness) =>
    ThemeData(colorSchemeSeed: Colors.blue, brightness: brightness);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: mode,
        home: const HomeScreen(),
      ),
    );
  }
}
