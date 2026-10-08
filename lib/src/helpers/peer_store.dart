import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:locsand/src/data/saved_peer.dart';
import 'package:locsand/src/helpers/atomic_file.dart';
import 'package:path_provider/path_provider.dart';

class SavedPeersStore {
  static final SavedPeersStore _instance = SavedPeersStore._internal();
  factory SavedPeersStore() => _instance;
  SavedPeersStore._internal();

  final Map<String, SavedPeer> _saved = {};
  File? _file;
  bool _loaded = false;
  Future<void>? _loading;
  final SerialQueue _queue = SerialQueue();

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/saved_peers.json');

    if (await _file!.exists()) {
      var decoded = <dynamic>[];
      try {
        decoded = jsonDecode(await _file!.readAsString()) as List<dynamic>;
      } catch (_) {
        await quarantineCorruptFile(_file!);
      }
      // One bad entry must not cost the user every other saved peer.
      for (final item in decoded) {
        try {
          final peer = SavedPeer.fromJson(item as Map<String, dynamic>);
          _saved[peer.deviceId] = peer;
        } catch (_) {}
      }
    }
    _loaded = true;
  }

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

  Future<void> _persist() {
    return _queue.run(() async {
      if (_file == null) return;
      // Encoded when the task runs, so the newest state always wins.
      final list = _saved.values.map((p) => p.toJson()).toList();
      await writeFileAtomic(_file!, jsonEncode(list));
    });
  }
}
