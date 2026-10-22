import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locsand/src/helpers/atomic_file.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('locsand_atomic_'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('SerialQueue', () {
    test('tasks run sequentially even when the first one is slower', () async {
      final q = SerialQueue();
      final order = <int>[];
      final f1 = q.run(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        order.add(1);
      });
      final f2 = q.run(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        order.add(2);
      });
      final f3 = q.run(() async => order.add(3));
      await Future.wait([f1, f2, f3]);
      expect(order, [1, 2, 3]);
    });

    test('returns the task result', () async {
      expect(await SerialQueue().run(() async => 42), 42);
    });

    test('an error in one task does not block the following ones', () async {
      final q = SerialQueue();
      final bad = q.run<void>(() async => throw StateError('x'));
      final good = q.run(() async => 'ok');
      await expectLater(bad, throwsStateError);
      expect(await good, 'ok');
    });
  });

  group('writeFileAtomic', () {
    test('writes the content and leaves no .tmp file behind', () async {
      final f = File('${dir.path}/data.json');
      await writeFileAtomic(f, '{"a":1}');
      expect(await f.readAsString(), '{"a":1}');
      expect(File('${f.path}.tmp').existsSync(), isFalse);
    });

    test('overwrites an existing file', () async {
      final f = File('${dir.path}/data.json');
      await writeFileAtomic(f, 'old');
      await writeFileAtomic(f, 'new');
      expect(await f.readAsString(), 'new');
    });

    test('Unicode content is preserved', () async {
      final f = File('${dir.path}/u.txt');
      await writeFileAtomic(f, 'Hello, ēūīāš 🙂');
      expect(await f.readAsString(), 'Hello, ēūīāš 🙂');
    });
  });

  group('quarantineCorruptFile', () {
    test('renames the file to .corrupt-<timestamp> and the original no longer exists', () async {
      final f = File('${dir.path}/settings.json')..writeAsStringSync('{corrupted');
      await quarantineCorruptFile(f);
      expect(f.existsSync(), isFalse);
      final moved = dir
          .listSync()
          .whereType<File>()
          .where((x) => x.path.contains('settings.json.corrupt-'));
      expect(moved.length, 1);
      expect(moved.single.readAsStringSync(), '{corrupted');
    });

    test('a missing file does not throw', () async {
      await quarantineCorruptFile(File('${dir.path}/missing.json'));
    });
  });
}
