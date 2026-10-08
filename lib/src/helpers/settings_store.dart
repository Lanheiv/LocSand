import 'dart:convert';
import 'dart:io';

import 'package:locsand/src/helpers/atomic_file.dart';
import 'package:path_provider/path_provider.dart';

class SettingsStore {
  static final SettingsStore _instance = SettingsStore._();
  factory SettingsStore() => _instance;
  SettingsStore._();

  Map<String, dynamic> _data = {};
  File? _file;
  Future<void>? _loading;
  final SerialQueue _queue = SerialQueue();

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/settings.json');
    try {
      if (await _file!.exists()) {
        final decoded = jsonDecode(await _file!.readAsString());
        if (decoded is! Map<String, dynamic>) throw const FormatException();
        _data = decoded;
      }
    } catch (_) {
      await quarantineCorruptFile(_file!);
      _data = {};
    }
  }

  Future<String?> get(String key) async {
    await _ensureLoaded();
    final value = _data[key];
    return value is String ? value : null;
  }

  Future<void> set(String key, String? value) async {
    await _ensureLoaded();
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
    await _queue.run(() => writeFileAtomic(_file!, jsonEncode(_data)));
  }
}
