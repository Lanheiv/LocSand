import 'package:flutter/services.dart' show rootBundle;
import 'package:toml/toml.dart';

Future<Map<String, dynamic>> loadConfig() async {
  final configString = await rootBundle.loadString('assets/config.toml');
  final document = TomlDocument.parse(configString);
  return document.toMap();
}