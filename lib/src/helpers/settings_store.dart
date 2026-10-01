import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class SettingsStore {
  static final SettingsStore _instance = SettingsStore._();
  factory SettingsStore() => _instance;
  SettingsStore._();

  Map<String, dynamic> _data = {};
  File? _file;
  Future<void>? _loading;

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/settings.json');
    try {
      if (await _file!.exists()) {
        _data = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
      }
    } catch (_) {
      _data = {};
    }
  }

  Future<String?> get(String key) async {
    await _ensureLoaded();
    return _data[key] as String?;
  }

  Future<void> set(String key, String? value) async {
    await _ensureLoaded();
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
    await _file!.writeAsString(jsonEncode(_data));
  }
}
