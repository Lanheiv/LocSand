import 'dart:async';
import 'dart:io';

/// Runs async tasks strictly one after another. Used so that two writes to
/// the same file can never interleave.
class SerialQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}

/// Writes [content] to a temporary file, flushes it to disk and only then
/// renames it over [file]. A crash in the middle leaves the old file intact.
Future<void> writeFileAtomic(File file, String content) async {
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(content, flush: true);
  await tmp.rename(file.path);
}

/// Moves an unreadable file out of the way instead of silently overwriting
/// it, so the user (or the developer) can still inspect it.
Future<void> quarantineCorruptFile(File file) async {
  try {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    await file.rename('${file.path}.corrupt-$stamp');
  } catch (_) {}
}
