import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:locsand/src/data/chat_message.dart';

class ChatHistoryStore {
  static final ChatHistoryStore _instance = ChatHistoryStore._internal();
  factory ChatHistoryStore() => _instance;
  ChatHistoryStore._internal();

  Directory? _dir;

  final Map<String, bool> _enabled = {};

  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() task) {
    final run = _tail.then((_) => task());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory('${supportDir.path}/chat_history');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  }

  Future<File> _fileFor(String deviceId) async {
    final dir = await _ensureDir();
    final safeId = deviceId.replaceAll(RegExp(r'[^A-Za-z0-9._\-]'), '_');
    return File('${dir.path}/$safeId.json');
  }

  Future<Map<String, dynamic>> _readRaw(String deviceId) async {
    final file = await _fileFor(deviceId);
    if (!await file.exists()) return {'enabled': false, 'messages': []};

    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      return decoded;
    } catch (_) {
      return {'enabled': false, 'messages': []};
    }
  }

  Future<void> _writeRaw(String deviceId, bool enabled, List<ChatMessage> messages) async {
    final file = await _fileFor(deviceId);
    final encoded = jsonEncode({
      'enabled': enabled,
      'messages': messages.map((m) => m.toJson()).toList(),
    });
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(encoded, flush: true);
    await tmp.rename(file.path);
  }

  Future<bool> _isEnabledNow(String deviceId) async {
    final cached = _enabled[deviceId];
    if (cached != null) return cached;
    final raw = await _readRaw(deviceId);
    final value = raw['enabled'] as bool? ?? false;
    _enabled[deviceId] = value;
    return value;
  }

  Future<bool> isEnabled(String deviceId) => _serial(() => _isEnabledNow(deviceId));

  Future<void> setEnabled(String deviceId, bool enabled, List<ChatMessage> currentMessages) {
    return _serial(() async {
      final raw = await _readRaw(deviceId);
      final existing = (raw['messages'] as List<dynamic>? ?? [])
          .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
          .toList();
      await _writeRaw(deviceId, enabled, enabled ? currentMessages : existing);
      _enabled[deviceId] = enabled;
    });
  }

  Future<void> saveIfEnabled(String deviceId, List<ChatMessage> messages) {
    return _serial(() async {
      if (!await _isEnabledNow(deviceId)) return;
      await _writeRaw(deviceId, true, messages);
    });
  }

  Future<List<ChatMessage>> load(String deviceId) {
    return _serial(() async {
      final raw = await _readRaw(deviceId);
      final messages = raw['messages'] as List<dynamic>? ?? [];
      return messages
          .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> deleteFile(String deviceId) {
    return _serial(() async {
      final file = await _fileFor(deviceId);
      if (await file.exists()) {
        await file.delete();
      }
      _enabled[deviceId] = false;
    });
  }

  Future<void> deleteAll() {
    return _serial(() async {
      final dir = await _ensureDir();
      await for (final entity in dir.list()) {
        if (entity is File) await entity.delete();
      }
      _enabled.clear();
    });
  }
}
