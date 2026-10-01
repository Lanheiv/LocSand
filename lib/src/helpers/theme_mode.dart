import 'package:flutter/material.dart';
import 'package:locsand/src/helpers/settings_store.dart';

final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

Future<void> loadThemeMode() async {
  try {
    final name = await SettingsStore().get('theme');
    themeMode.value = ThemeMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ThemeMode.system,
    );
  } catch (_) {}
}

Future<void> setThemeMode(ThemeMode mode) async {
  themeMode.value = mode;
  await SettingsStore().set('theme', mode.name);
}
