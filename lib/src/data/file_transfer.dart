enum FileTransferDirection { incoming, outgoing }

enum FileTransferStatus {
  offered,
  declined,
  inProgress,
  completed,
  failed,
}

class FileTransfer {
  final String transferId;
  final String deviceId;
  final String name;
  final int size;
  final FileTransferDirection direction;
  final DateTime startedAt;

  FileTransferStatus status;
  int bytesTransferred;

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

  double get progress => size <= 0 ? 0 : (bytesTransferred / size).clamp(0, 1).toDouble();
}