import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locsand/src/helpers/line_framer.dart';

void main() {
  test('splits frames that arrive in pieces', () {
    final f = LineFramer(maxFrameBytes: 100);
    expect(f.add(utf8.encode('{"a":1')), isEmpty);
    final out = f.add(utf8.encode('}\n{"b":2}\n{"c"'));
    expect(out.map(utf8.decode), ['{"a":1}', '{"b":2}']);
    expect(f.add(utf8.encode(':3}\n')).map(utf8.decode), ['{"c":3}']);
  });

  test('accepts a frame of exactly the limit', () {
    final f = LineFramer(maxFrameBytes: 10);
    expect(f.add(utf8.encode('${'x' * 10}\n')).single.length, 10);
  });

  test('rejects an oversized frame before it is complete', () {
    final f = LineFramer(maxFrameBytes: 10);
    expect(() => f.add(utf8.encode('x' * 11)), throwsA(isA<FrameTooLargeException>()));
  });

  test('rejects an oversized frame that is built up over many chunks', () {
    final f = LineFramer(maxFrameBytes: 10);
    f.add(utf8.encode('xxxxxx'));
    expect(() => f.add(utf8.encode('xxxxxx')), throwsA(isA<FrameTooLargeException>()));
  });

  test('empty lines produce empty frames the caller can skip', () {
    final f = LineFramer();
    expect(f.add(utf8.encode('\n\n')).length, 2);
  });
}
