enum FileTransferDirection { incoming, outgoing }

enum FileTransferStatus {
  offered,
  accepted,
  declined,
  inProgress,
  completed,
  failed,
}

/// Tracks the state of a single file transfer, in either direction, over
/// an already-established peer connection. Kept in SessionData.fileTransfers
/// so the UI can render progress without the transfer logic itself living
/// in a widget.
class FileTransfer {
  final String transferId;
  final String deviceId;
  final String name;
  final int size;
  final FileTransferDirection direction;
  final DateTime startedAt;

  FileTransferStatus status;
  int bytesTransferred;

  /// Where the bytes are being read from (outgoing) or written to
  /// (incoming) on this device's local filesystem.
  String? localPath;

  FileTransfer({
    required this.transferId,
    required this.deviceId,
    required this.name,
    required this.size,
    required this.direction,
    required this.startedAt,
    this.status = FileTransferStatus.offered,
    this.bytesTransferred = 0,
    this.localPath,
  });

  double get progress => size <= 0 ? 0 : (bytesTransferred / size).clamp(0, 1);
}