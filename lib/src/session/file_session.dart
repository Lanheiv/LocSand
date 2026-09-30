import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:locsand/src/data/file_transfer.dart';
import 'package:locsand/src/helpers/receive_folder.dart';
import 'package:locsand/src/tasks/tcp_connection.dart';

mixin FileSession on ChangeNotifier {
  String? get userId;
  TcpPeerConnection? liveConnection(String deviceId);

  final Map<String, FileTransfer> fileTransfers = {};
  final Map<String, IOSink> _sinks = {};

  void Function(FileTransfer transfer, void Function(bool accept) respond)?
      onIncomingFileOffer;

  List<FileTransfer> fileTransfersFor(String deviceId) => fileTransfers.values
      .where((t) => t.deviceId == deviceId)
      .toList()
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  Future<FileTransfer> sendFile(String deviceId, File file) async {
    final size = await file.length();
    final conn = liveConnection(deviceId);
    if (conn == null) throw StateError('Not connected');

    final transfer = FileTransfer(
      transferId: '${userId ?? 'me'}-${DateTime.now().microsecondsSinceEpoch}',
      deviceId: deviceId,
      name: file.path.split(RegExp(r'[\\/]')).last,
      size: size,
      direction: FileTransferDirection.outgoing,
      startedAt: DateTime.now(),
      localPath: file.path,
    );

    conn.send({
      'type': 'file_offer',
      'transferId': transfer.transferId,
      'name': transfer.name,
      'size': size,
    });
    fileTransfers[transfer.transferId] = transfer;
    notifyListeners();
    return transfer;
  }

  void handleFileMessage(String deviceId, String type, Map<String, dynamic> msg) {
    switch (type) {
      case 'file_offer':
        _onOffer(deviceId, msg);
      case 'file_accept':
        _onAccept(deviceId, msg);
      case 'file_decline':
        _onDecline(deviceId, msg);
      case 'file_chunk':
        _onChunk(deviceId, msg);
      case 'file_complete':
        unawaited(_onComplete(deviceId, msg));
    }
  }

  FileTransfer? _owned(String deviceId, Object? id, FileTransferDirection dir) {
    final t = fileTransfers[id];
    return t != null && t.deviceId == deviceId && t.direction == dir ? t : null;
  }

  void _onOffer(String deviceId, Map<String, dynamic> msg) {
    final id = msg['transferId'];
    final name = msg['name'];
    final size = msg['size'];
    if (id is! String || id.isEmpty || id.length > 128) return;
    if (name is! String || size is! int || size < 0) return;
    if (fileTransfers.containsKey(id)) return;

    final transfer = FileTransfer(
      transferId: id,
      deviceId: deviceId,
      name: name,
      size: size,
      direction: FileTransferDirection.incoming,
      startedAt: DateTime.now(),
    );
    fileTransfers[id] = transfer;
    notifyListeners();

    final handler = onIncomingFileOffer;
    if (handler == null) {
      _decline(transfer);
      return;
    }
    handler(transfer, (accept) {
      if (accept) {
        unawaited(_accept(transfer));
      } else {
        _decline(transfer);
      }
    });
  }

  Future<void> _accept(FileTransfer transfer) async {
    final conn = liveConnection(transfer.deviceId);
    if (conn == null || transfer.status != FileTransferStatus.offered) {
      _abort(transfer);
      return;
    }
    try {
      final dir = await receiveDirectory();
      await dir.create(recursive: true);
      final file = _uniqueFile(dir, _safeName(transfer.name));
      await file.create();
      transfer.localPath = file.path;
      _sinks[transfer.transferId] = file.openWrite();
      transfer.status = FileTransferStatus.inProgress;
      notifyListeners();
      conn.send({'type': 'file_accept', 'transferId': transfer.transferId});
    } catch (_) {
      _abort(transfer);
    }
  }

  void _decline(FileTransfer transfer) {
    transfer.status = FileTransferStatus.declined;
    notifyListeners();
    _sendDecline(transfer);
  }

  void _sendDecline(FileTransfer transfer) {
    try {
      liveConnection(transfer.deviceId)
          ?.send({'type': 'file_decline', 'transferId': transfer.transferId});
    } catch (_) {}
  }

  void _onAccept(String deviceId, Map<String, dynamic> msg) {
    final t = _owned(deviceId, msg['transferId'], FileTransferDirection.outgoing);
    if (t == null || t.status != FileTransferStatus.offered) return;
    t.status = FileTransferStatus.inProgress;
    notifyListeners();
    unawaited(_stream(t));
  }

  void _onDecline(String deviceId, Map<String, dynamic> msg) {
    final t = _owned(deviceId, msg['transferId'], FileTransferDirection.outgoing);
    if (t == null ||
        (t.status != FileTransferStatus.offered &&
            t.status != FileTransferStatus.inProgress)) {
      return;
    }
    t.status = FileTransferStatus.declined;
    notifyListeners();
  }

  Future<void> _stream(FileTransfer t) async {
    try {
      await for (final chunk in File(t.localPath!).openRead()) {
        if (t.status != FileTransferStatus.inProgress) return;
        final conn = liveConnection(t.deviceId);
        if (conn == null) throw StateError('Connection lost');
        conn.send({
          'type': 'file_chunk',
          'transferId': t.transferId,
          'data': base64Encode(chunk),
        });
        await conn.flush();
        t.bytesTransferred += chunk.length;
        notifyListeners();
      }
      if (t.status != FileTransferStatus.inProgress) return;
      final conn = liveConnection(t.deviceId);
      if (conn == null) throw StateError('Connection lost');
      conn.send({'type': 'file_complete', 'transferId': t.transferId});
      await conn.flush();
      t.status = FileTransferStatus.completed;
    } catch (_) {
      t.status = FileTransferStatus.failed;
    }
    notifyListeners();
  }

  void _onChunk(String deviceId, Map<String, dynamic> msg) {
    final data = msg['data'];
    final t = _owned(deviceId, msg['transferId'], FileTransferDirection.incoming);
    final sink = t == null ? null : _sinks[t.transferId];
    if (t == null || sink == null || data is! String) return;
    if (t.status != FileTransferStatus.inProgress) return;

    try {
      final bytes = base64Decode(data);
      if (t.bytesTransferred + bytes.length > t.size) {
        _abort(t);
        return;
      }
      sink.add(bytes);
      t.bytesTransferred += bytes.length;
      notifyListeners();
    } catch (_) {
      _abort(t);
    }
  }

  Future<void> _onComplete(String deviceId, Map<String, dynamic> msg) async {
    final t = _owned(deviceId, msg['transferId'], FileTransferDirection.incoming);
    if (t == null || t.status != FileTransferStatus.inProgress) return;
    if (t.bytesTransferred != t.size) {
      _abort(t);
      return;
    }
    try {
      await _sinks.remove(t.transferId)?.close();
      t.status = FileTransferStatus.completed;
    } catch (_) {
      t.status = FileTransferStatus.failed;
    }
    notifyListeners();
  }

  void _abort(FileTransfer t) {
    final sink = _sinks.remove(t.transferId);
    final path = t.localPath;
    t.status = FileTransferStatus.failed;
    notifyListeners();
    _sendDecline(t);
    unawaited(() async {
      try {
        await sink?.close();
        if (path != null) await File(path).delete();
      } catch (_) {}
    }());
  }

  void failTransfersFor(String deviceId) {
    for (final t in fileTransfers.values.toList()) {
      if (t.deviceId != deviceId) continue;
      if (t.status != FileTransferStatus.inProgress &&
          t.status != FileTransferStatus.offered) {
        continue;
      }
      if (t.direction == FileTransferDirection.incoming) {
        _abort(t);
      } else {
        t.status = FileTransferStatus.failed;
      }
    }
    notifyListeners();
  }

  String _safeName(String raw) {
    final base = raw.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).lastOrNull;
    final name = (base ?? '').replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_').trim();
    return name.isEmpty || name == '.' || name == '..' ? 'received_file' : name;
  }

  File _uniqueFile(Directory dir, String name) {
    var file = File('${dir.path}/$name');
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 1; file.existsSync(); i++) {
      file = File('${dir.path}/$base ($i)$ext');
    }
    return file;
  }
}
