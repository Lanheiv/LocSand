import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locsand/src/helpers/atomic_file.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('locsand_test_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('writeFileAtomic creates and replaces a file without leaving a tmp file', () async {
    final f = File('${dir.path}/data.json');
    await writeFileAtomic(f, 'one');
    await writeFileAtomic(f, 'two');
    expect(await f.readAsString(), 'two');
    expect(File('${f.path}.tmp').existsSync(), isFalse);
  });

  test('quarantineCorruptFile moves the file aside', () async {
    final f = File('${dir.path}/bad.json')..writeAsStringSync('{not json');
    await quarantineCorruptFile(f);
    expect(f.existsSync(), isFalse);
    expect(dir.listSync().whereType<File>().single.path, contains('.corrupt-'));
  });

  test('SerialQueue runs tasks in order even when earlier ones are slower', () async {
    final q = SerialQueue();
    final order = <int>[];
    final a = q.run(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      order.add(1);
    });
    final b = q.run(() async => order.add(2));
    await Future.wait([a, b]);
    expect(order, [1, 2]);
  });

  test('SerialQueue keeps running after a task fails', () async {
    final q = SerialQueue();
    await expectLater(q.run(() async => throw StateError('x')), throwsStateError);
    expect(await q.run(() async => 7), 7);
  });
}
