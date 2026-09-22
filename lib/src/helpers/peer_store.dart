import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:locsand/src/data/saved_peer.dart';

class SavedPeersStore {
  static final SavedPeersStore _instance = SavedPeersStore._internal();
  factory SavedPeersStore() => _instance;
  SavedPeersStore._internal();

  final Map<String, SavedPeer> _peers = {};
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
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        _peers
          ..clear()
          ..addEntries(decoded.entries.map(
            (e) => MapEntry(
              e.key,
              SavedPeer.fromJson(e.value as Map<String, dynamic>),
            ),
          ));
      } catch (_) {
        _peers.clear();
      }
    }
    _loaded = true;
  }

  List<SavedPeer> get all => _peers.values.toList();

  SavedPeer? get(String deviceId) => _peers[deviceId];

  Future<void> save(SavedPeer peer) async {
    await ensureLoaded();
    _peers[peer.deviceId] = peer;
    await _persist();
  }

  Future<void> remove(String deviceId) async {
    await ensureLoaded();
    if (_peers.remove(deviceId) != null) {
      await _persist();
    }
  }

  Future<void> _persist() async {
    if (_file == null) return;
    final encoded = jsonEncode(_peers.map((k, v) => MapEntry(k, v.toJson())));
    await _file!.writeAsString(encoded);
  }
}