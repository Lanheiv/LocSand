import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:locsand/src/data/saved_peer.dart';

/// Persists the list of peers the user has explicitly chosen to "save",
/// so they're still there the next time the app starts — separate from
/// `SessionData.peers`, which only reflects who is currently reachable on
/// the network right now.
class SavedPeersStore {
  static final SavedPeersStore _instance = SavedPeersStore._internal();
  factory SavedPeersStore() => _instance;
  SavedPeersStore._internal();

  final Map<String, SavedPeer> _saved = {};
  File? _file;
  bool _loaded = false;
  Future<void>? _loading;

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/saved_peers.json');

    if (await _file!.exists()) {
      try {
        final content = await _file!.readAsString();
        final decoded = jsonDecode(content) as List<dynamic>;
        for (final item in decoded) {
          final peer = SavedPeer.fromJson(item as Map<String, dynamic>);
          _saved[peer.deviceId] = peer;
        }
      } catch (_) {
        // Corrupt file — start with an empty saved list rather than crash.
        _saved.clear();
      }
    }
    _loaded = true;
  }

  /// Synchronous — assumes [ensureLoaded] has already completed, which it
  /// will have by the time any UI or connection-handling code runs, since
  /// it's awaited once during app startup.
  List<SavedPeer> get all => _saved.values.toList();

  bool isSaved(String deviceId) => _saved.containsKey(deviceId);

  SavedPeer? get(String deviceId) => _saved[deviceId];

  Future<void> save(
    String deviceId,
    String name, {
    String lastKnownIp = '',
    int lastKnownPort = 0,
  }) async {
    await ensureLoaded();
    _saved[deviceId] = SavedPeer(
      deviceId: deviceId,
      name: name,
      lastKnownIp: lastKnownIp,
      lastKnownPort: lastKnownPort,
      savedAt: DateTime.now(),
    );
    await _persist();
  }

  Future<void> remove(String deviceId) async {
    await ensureLoaded();
    if (_saved.remove(deviceId) != null) {
      await _persist();
    }
  }

  Future<void> _persist() async {
    if (_file == null) return;
    final list = _saved.values.map((p) => p.toJson()).toList();
    await _file!.writeAsString(jsonEncode(list));
  }
}