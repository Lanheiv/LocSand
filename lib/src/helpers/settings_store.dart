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

  Future<String?> getReceiveDir() async {
    await _ensureLoaded();
    return _data['receiveDir'] as String?;
  }

  Future<void> setReceiveDir(String? dir) async {
    await _ensureLoaded();
    if (dir == null) {
      _data.remove('receiveDir');
    } else {
      _data['receiveDir'] = dir;
    }
    await _file!.writeAsString(jsonEncode(_data));
  }
}
