import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:locsand/src/data/peer_data.dart';
import 'package:locsand/src/data/saved_peer.dart';
import 'package:locsand/src/helpers/peer_store.dart';
import 'package:locsand/src/tasks/tcp_connection.dart';

mixin SavedPeersSession on ChangeNotifier {
  String? get userId;
  String? get userName;
  PeerData? getPeer(String deviceId);
  TcpPeerConnection? liveConnection(String deviceId);
  Future<void> ensureChatHistoryLoaded(String deviceId);

  void Function(String deviceId, String name, void Function(bool accept) respond)?
      onIncomingSaveRequest;

  final Set<String> _savePrompts = {};

  List<SavedPeer> get allSavedPeers => SavedPeersStore().all;

  bool isPeerSaved(String deviceId) => SavedPeersStore().isSaved(deviceId);

  Future<void> loadSavedPeers() async {
    final store = SavedPeersStore();
    await store.ensureLoaded();
    for (final s in store.all) {
      unawaited(ensureChatHistoryLoaded(s.deviceId));
    }
    notifyListeners();
  }

  Future<void> savePeer(String deviceId) async {
    await _remember(deviceId, getPeer(deviceId)?.name ?? deviceId);
    liveConnection(deviceId)?.send({'type': 'save', 'name': userName});
  }

  void handleSaveRequest(String deviceId, String name) {
    final handler = onIncomingSaveRequest;
    if (handler == null || isPeerSaved(deviceId) || !_savePrompts.add(deviceId)) {
      return;
    }
    handler(deviceId, name.length > 64 ? name.substring(0, 64) : name, (accept) {
      _savePrompts.remove(deviceId);
      if (accept) unawaited(_remember(deviceId, name));
    });
  }

  Future<void> forgetSavedPeer(String deviceId) async {
    await SavedPeersStore().remove(deviceId);
    notifyListeners();
  }

  Future<void> _remember(String deviceId, String name) async {
    final peer = getPeer(deviceId);
    await SavedPeersStore().save(
      deviceId,
      name,
      lastKnownIp: peer?.ip ?? liveConnection(deviceId)?.ip ?? '',
      lastKnownPort: peer?.port ?? 0,
    );
    notifyListeners();
  }
}
