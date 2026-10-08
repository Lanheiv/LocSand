import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:locsand/src/data/file_transfer.dart';
import 'package:locsand/src/helpers/file_names.dart';
import 'package:locsand/src/helpers/receive_folder.dart';
import 'package:locsand/src/tasks/tcp_connection.dart';

mixin FileSession on ChangeNotifier {
  /// Per-file limit (8 GiB). Larger offers are declined automatically.
  static const int maxFileBytes = 8 * 1024 * 1024 * 1024;
  static const int _chunkBytes = 128 * 1024;
  // 128 KiB of data is ~171 Ki characters of base64; allow a little slack.
  static const int _maxChunkBase64 = 180 * 1024;
  // Wait for the socket to drain only every few chunks (~1 MiB), not after
  // each one: keeps the pipe full while still bounding buffered memory.
  static const int _flushEveryChunks = 8;
  static const int _maxRawNameLength = 1024;
  static const int _maxPendingOffers = 3;
  static const Duration _ackTimeout = Duration(seconds: 30);
  static const Duration _progressInterval = Duration(milliseconds: 250);
  static const String _partSuffix = '.locsand-part';

  String? get userId;
  TcpPeerConnection? liveConnection(String deviceId);

  final Map<String, FileTransfer> fileTransfers = {};
  final Map<String, IOSink> _sinks = {};
  final Map<String, String> _finalPaths = {};
  final Map<String, Completer<bool>> _acks = {};
  final Map<String, DateTime> _lastNotify = {};

  void Function(FileTransfer transfer, void Function(bool accept) respond)?
      onIncomingFileOffer;

  List<FileTransfer> fileTransfersFor(String deviceId) => fileTransfers.values
      .where((t) => t.deviceId == deviceId)
      .toList()
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  Future<FileTransfer> sendFile(String deviceId, File file) async {
    final size = await file.length();
    if (size > maxFileBytes) {
      throw StateError('File is too large (limit is ${maxFileBytes ~/ (1024 * 1024 * 1024)} GiB)');
    }
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
      case 'file_received':
        _onReceived(deviceId, msg);
    }
  }

  FileTransfer? _owned(String deviceId, Object? id, FileTransferDirection dir) {
    final t = fileTransfers[id];
    return t != null && t.deviceId == deviceId && t.direction == dir ? t : null;
  }

  void _declineById(String deviceId, String transferId) {
    try {
      liveConnection(deviceId)?.send({'type': 'file_decline', 'transferId': transferId});
    } catch (_) {}
  }

  void _onOffer(String deviceId, Map<String, dynamic> msg) {
    final id = msg['transferId'];
    final name = msg['name'];
    final size = msg['size'];
    if (id is! String || id.isEmpty || id.length > 128) return;
    if (name is! String || name.isEmpty || name.length > _maxRawNameLength) return;
    if (size is! int || size < 0) return;
    if (fileTransfers.containsKey(id)) return;

    // Too many unanswered offers, or a file above the limit: decline without
    // bothering the user and without keeping any state for it.
    final pending = fileTransfers.values.where((t) =>
        t.direction == FileTransferDirection.incoming &&
        t.status == FileTransferStatus.offered);
    if (pending.length >= _maxPendingOffers || size > maxFileBytes) {
      _declineById(deviceId, id);
      return;
    }

    final transfer = FileTransfer(
      transferId: id,
      deviceId: deviceId,
      name: safeFileName(name),
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

  /// Picks a free final name and creates the matching ".locsand-part" file.
  /// The data is written to the part file and only renamed to the final name
  /// once the whole file has arrived, so a crash never leaves a half-written
  /// file that looks like a finished document.
  (File finalFile, File partFile) _reserve(Directory dir, String name) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';

    var finalFile = File('${dir.path}/$name');
    var part = File('${finalFile.path}$_partSuffix');
    for (var i = 1; finalFile.existsSync() || part.existsSync(); i++) {
      finalFile = File('${dir.path}/$base ($i)$ext');
      part = File('${finalFile.path}$_partSuffix');
    }
    part.createSync();
    return (finalFile, part);
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
      if (transfer.status != FileTransferStatus.offered) return;

      final (finalFile, partFile) = _reserve(dir, safeFileName(transfer.name));
      transfer.localPath = partFile.path;
      _finalPaths[transfer.transferId] = finalFile.path;

      final sink = partFile.openWrite();
      _sinks[transfer.transferId] = sink;
      // Disk full / write errors surface here, asynchronously.
      unawaited(sink.done.catchError((Object _) {
        if (transfer.status == FileTransferStatus.inProgress) _abort(transfer);
      }));

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

  void _sendDecline(FileTransfer transfer) =>
      _declineById(transfer.deviceId, transfer.transferId);

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
    final ack = _acks[t.transferId];
    if (ack != null && !ack.isCompleted) ack.complete(false);
    notifyListeners();
  }

  void _onReceived(String deviceId, Map<String, dynamic> msg) {
    final t = _owned(deviceId, msg['transferId'], FileTransferDirection.outgoing);
    if (t == null) return;
    final ack = _acks[t.transferId];
    if (ack != null && !ack.isCompleted) ack.complete(msg['ok'] == true);
  }

  Future<void> _stream(FileTransfer t) async {
    var sinceFlush = 0;
    try {
      await for (final chunk in File(t.localPath!).openRead()) {
        for (var i = 0; i < chunk.length; i += _chunkBytes) {
          if (t.status != FileTransferStatus.inProgress) return;
          final conn = liveConnection(t.deviceId);
          if (conn == null) throw StateError('Connection lost');
          final piece = chunk.sublist(i, min(i + _chunkBytes, chunk.length));
          conn.send({
            'type': 'file_chunk',
            'transferId': t.transferId,
            'data': base64Encode(piece),
          });
          if (++sinceFlush >= _flushEveryChunks) {
            sinceFlush = 0;
            await conn.flush();
          }
          t.bytesTransferred += piece.length;
          _progress(t);
        }
      }
      if (t.status != FileTransferStatus.inProgress) return;
      if (t.bytesTransferred != t.size) throw StateError('File changed while sending');

      final conn = liveConnection(t.deviceId);
      if (conn == null) throw StateError('Connection lost');

      // Register for the receiver's verdict *before* sending file_complete.
      final ack = Completer<bool>();
      _acks[t.transferId] = ack;
      conn.send({'type': 'file_complete', 'transferId': t.transferId});
      await conn.flush();

      // "Completed" only once the receiver confirms the file is closed,
      // verified and renamed - not when the bytes left our socket buffer.
      final ok = await ack.future.timeout(_ackTimeout, onTimeout: () => false);
      if (t.status == FileTransferStatus.inProgress) {
        t.status = ok ? FileTransferStatus.completed : FileTransferStatus.failed;
      }
    } catch (_) {
      if (t.status == FileTransferStatus.inProgress) t.status = FileTransferStatus.failed;
    } finally {
      _acks.remove(t.transferId);
      _lastNotify.remove(t.transferId);
    }
    notifyListeners();
  }

  void _onChunk(String deviceId, Map<String, dynamic> msg) {
    final data = msg['data'];
    final t = _owned(deviceId, msg['transferId'], FileTransferDirection.incoming);
    final sink = t == null ? null : _sinks[t.transferId];
    if (t == null || sink == null || data is! String) return;
    if (t.status != FileTransferStatus.inProgress) return;

    // Check the size of the *encoded* chunk before decoding it.
    if (data.length > _maxChunkBase64) {
      _abort(t);
      return;
    }
    try {
      final bytes = base64Decode(data);
      if (t.bytesTransferred + bytes.length > t.size) {
        _abort(t);
        return;
      }
      sink.add(bytes);
      t.bytesTransferred += bytes.length;
      _progress(t);
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

    final sink = _sinks.remove(t.transferId);
    final partPath = t.localPath;
    final finalPath = _finalPaths.remove(t.transferId);
    var ok = false;
    try {
      await sink?.close();
      if (partPath != null && finalPath != null) {
        await File(partPath).rename(finalPath);
        t.localPath = finalPath;
        ok = true;
      }
    } catch (_) {
      ok = false;
    }
    if (!ok && partPath != null) {
      try {
        await File(partPath).delete();
      } catch (_) {}
    }

    if (t.status == FileTransferStatus.inProgress) {
      t.status = ok ? FileTransferStatus.completed : FileTransferStatus.failed;
    }
    _lastNotify.remove(t.transferId);
    notifyListeners();
    try {
      liveConnection(t.deviceId)
          ?.send({'type': 'file_received', 'transferId': t.transferId, 'ok': ok});
    } catch (_) {}
  }

  void _abort(FileTransfer t) {
    final sink = _sinks.remove(t.transferId);
    _finalPaths.remove(t.transferId);
    _lastNotify.remove(t.transferId);
    final path = t.localPath;
    final wasActive = t.status != FileTransferStatus.failed;
    t.status = FileTransferStatus.failed;
    notifyListeners();
    if (wasActive) _sendDecline(t);
    unawaited(() async {
      try {
        await sink?.close();
      } catch (_) {}
      try {
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
        final ack = _acks[t.transferId];
        if (ack != null && !ack.isCompleted) ack.complete(false);
      }
    }
    notifyListeners();
  }

  /// Notifies the UI at most a few times per second during a transfer instead
  /// of once per network chunk.
  void _progress(FileTransfer t) {
    final now = DateTime.now();
    final last = _lastNotify[t.transferId];
    if (last == null ||
        now.difference(last) >= _progressInterval ||
        t.bytesTransferred >= t.size) {
      _lastNotify[t.transferId] = now;
      notifyListeners();
    }
  }
}
