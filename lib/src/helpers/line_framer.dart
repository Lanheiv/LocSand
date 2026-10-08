import 'dart:typed_data';

class FrameTooLargeException implements Exception {
  final int limit;
  FrameTooLargeException(this.limit);

  @override
  String toString() => 'Protocol frame is larger than $limit bytes';
}

/// Splits a byte stream into newline-terminated frames and refuses to buffer
/// more than [maxFrameBytes] for one frame. Unlike `LineSplitter`, the limit
/// is enforced *before* the whole line is in memory, so a hostile peer cannot
/// make the app allocate hundreds of megabytes.
class LineFramer {
  LineFramer({this.maxFrameBytes = 128 * 1024});

  final int maxFrameBytes;
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  /// Feeds one chunk from the socket and returns every frame completed by it
  /// (without the trailing newline). Throws [FrameTooLargeException] when a
  /// frame exceeds the limit; the framer must not be reused afterwards.
  List<Uint8List> add(List<int> data) {
    final frames = <Uint8List>[];
    var start = 0;
    while (start < data.length) {
      final newline = data.indexOf(10, start);
      final end = newline == -1 ? data.length : newline;
      if (_buffer.length + (end - start) > maxFrameBytes) {
        _buffer.clear();
        throw FrameTooLargeException(maxFrameBytes);
      }
      if (end > start) _buffer.add(data.sublist(start, end));
      if (newline == -1) break;
      frames.add(_buffer.takeBytes());
      start = newline + 1;
    }
    return frames;
  }
}
