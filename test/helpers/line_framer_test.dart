import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locsand/src/helpers/line_framer.dart';

List<int> b(String s) => utf8.encode(s);
List<String> texts(List<Uint8List> f) => f.map(utf8.decode).toList();

void main() {
  group('LineFramer', () {
    test('a single complete frame', () {
      final f = LineFramer();
      expect(texts(f.add(b('{"a":1}\n'))), ['{"a":1}']);
    });

    test('multiple frames in one chunk', () {
      final f = LineFramer();
      expect(texts(f.add(b('one\ntwo\nthree\n'))), ['one', 'two', 'three']);
    });

    test('a frame split across multiple chunks', () {
      final f = LineFramer();
      expect(f.add(b('hel')), isEmpty);
      expect(f.add(b('lo wo')), isEmpty);
      expect(texts(f.add(b('rld\nnext'))), ['hello world']);
      expect(texts(f.add(b('\n'))), ['next']);
    });

    test('empty lines produce empty frames', () {
      final f = LineFramer();
      final frames = f.add(b('\n\n'));
      expect(frames.length, 2);
      expect(frames.every((x) => x.isEmpty), isTrue);
    });

    test('a multi-byte UTF-8 character split between chunks', () {
      final f = LineFramer();
      final bytes = utf8.encode('ā'); // 2 bytes
      expect(f.add([bytes[0]]), isEmpty);
      final frames = f.add([bytes[1], 10]);
      expect(texts(frames), ['ā']);
    });

    test('a frame of exactly the maximum length is allowed', () {
      final f = LineFramer(maxFrameBytes: 10);
      expect(texts(f.add(b('${'a' * 10}\n'))), ['a' * 10]);
    });

    test('a frame one byte longer throws FrameTooLargeException', () {
      final f = LineFramer(maxFrameBytes: 10);
      expect(() => f.add(b('${'a' * 11}\n')),
          throwsA(isA<FrameTooLargeException>()));
    });

    test('the limit is enforced even when the frame arrives in parts (no newline)', () {
      final f = LineFramer(maxFrameBytes: 10);
      expect(f.add(b('a' * 6)), isEmpty);
      expect(() => f.add(b('a' * 5)), throwsA(isA<FrameTooLargeException>()));
    });

    test('the exception message contains the limit', () {
      expect(FrameTooLargeException(42).toString(), contains('42'));
    });
  });
}
