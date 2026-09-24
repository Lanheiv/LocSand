import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:locsand/src/data/chat_message.dart';

/// Persists chat history to disk, one JSON file per peer, so a
/// conversation survives an app restart — separate from
/// `SessionData.chatMessages`, which is in-memory only and is cleared
/// whenever [SessionData.clear] runs (e.g. on sign-out).
///
/// Saving is opt-in per peer: nothing is written until the user turns
/// history on for that conversation (see `enabled`, below). Each file
/// stores that on/off decision together with the messages, so "delete"
/// removes the file entirely and there's nothing left to turn off — the
/// decision and the data live and die together.
class ChatHistoryStore {
  static final ChatHistoryStore _instance = ChatHistoryStore._internal();
  factory ChatHistoryStore() => _instance;
  ChatHistoryStore._internal();

  Directory? _dir;

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
    // deviceId is our own generated identifier (see core_protocols), not
    // peer-supplied text, but it's sanitized anyway before use in a path
    // for the same reason file transfer names are: defense in depth.
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
      // Corrupt file — treat as if nothing were saved rather than crash.
      return {'enabled': false, 'messages': []};
    }
  }

  Future<void> _writeRaw(String deviceId, bool enabled, List<ChatMessage> messages) async {
    final file = await _fileFor(deviceId);
    final encoded = jsonEncode({
      'enabled': enabled,
      'messages': messages.map((m) => m.toJson()).toList(),
    });
    await file.writeAsString(encoded);
  }

  /// Whether history saving is currently turned on for [deviceId].
  /// Defaults to false — a peer's conversation is not saved to disk
  /// until the user explicitly turns this on.
  Future<bool> isEnabled(String deviceId) async {
    final raw = await _readRaw(deviceId);
    return raw['enabled'] as bool? ?? false;
  }

  /// Turns history saving on or off for [deviceId]. Turning it on saves
  /// [currentMessages] immediately, so nothing already in the
  /// conversation is lost. Turning it off leaves whatever was already
  /// saved on disk untouched — call [deleteFile] to remove that too.
  Future<void> setEnabled(String deviceId, bool enabled, List<ChatMessage> currentMessages) async {
    final raw = await _readRaw(deviceId);
    final existing = (raw['messages'] as List<dynamic>? ?? [])
        .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
        .toList();
    await _writeRaw(deviceId, enabled, enabled ? currentMessages : existing);
  }

  /// Appends to the on-disk save for [deviceId] with the current message
  /// list, but only if saving is turned on for that peer — a no-op
  /// otherwise, so callers can call this unconditionally after every
  /// message without checking [isEnabled] themselves first.
  Future<void> saveIfEnabled(String deviceId, List<ChatMessage> messages) async {
    final raw = await _readRaw(deviceId);
    final enabled = raw['enabled'] as bool? ?? false;
    if (!enabled) return;
    await _writeRaw(deviceId, true, messages);
  }

  /// Loads the previously saved history for [deviceId], or an empty list
  /// if nothing has been saved (or the file is unreadable/corrupt).
  Future<List<ChatMessage>> load(String deviceId) async {
    final raw = await _readRaw(deviceId);
    final messages = raw['messages'] as List<dynamic>? ?? [];
    return messages
        .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Deletes the saved history file for [deviceId], if one exists. This
  /// removes the saved messages and the on/off decision together — after
  /// this, [isEnabled] goes back to reporting false, as if history had
  /// never been turned on for this peer.
  Future<void> deleteFile(String deviceId) async {
    final file = await _fileFor(deviceId);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
