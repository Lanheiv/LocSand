import 'package:flutter_test/flutter_test.dart';
import 'package:locsand/src/helpers/file_names.dart';

void main() {
  group('safeFileName', () {
    test('a normal name stays unchanged', () {
      expect(safeFileName('report.pdf'), 'report.pdf');
      expect(safeFileName('hello world ēū.txt'), 'hello world ēū.txt');
      expect(safeFileName('.bashrc'), '.bashrc');
    });

    test('strips path components (path traversal)', () {
      expect(safeFileName('../../etc/passwd'), 'passwd');
      expect(safeFileName(r'C:\Users\x\evil.exe'), 'evil.exe');
      expect(safeFileName('/abs/path/file.txt'), 'file.txt');
      expect(safeFileName('a/b/'), 'b');
    });

    test('empty or dots-only names become received_file', () {
      expect(safeFileName(''), 'received_file');
      expect(safeFileName('.'), 'received_file');
      expect(safeFileName('..'), 'received_file');
      expect(safeFileName('///'), 'received_file');
      expect(safeFileName('   '), 'received_file');
    });

    test('forbidden characters and control characters → _', () {
      expect(safeFileName('a<b>c:d"e|f?g*h.txt'), 'a_b_c_d_e_f_g_h.txt');
      expect(safeFileName('a\x00b\n.txt'), 'a_b_.txt');
    });

    test('strips trailing dots and spaces', () {
      expect(safeFileName('file.txt. . '), 'file.txt');
    });

    test('Windows reserved names', () {
      expect(safeFileName('con.txt'), '_con.txt');
      expect(safeFileName('CON'), '_CON');
      expect(safeFileName('nul.tar.gz'), '_nul.tar.gz');
      expect(safeFileName('com1'), '_com1');
      expect(safeFileName('LPT9.log'), '_LPT9.log');
      expect(safeFileName('console.txt'), 'console.txt');
    });

    test('a long name is truncated and the extension is preserved', () {
      final r = safeFileName('${'a' * 300}.txt');
      expect(r.length, lessThanOrEqualTo(120));
      expect(r.endsWith('.txt'), isTrue);
    });

    test('an overly long extension is trimmed to 16 characters', () {
      final r = safeFileName('x.${'e' * 40}');
      expect(r.substring(r.lastIndexOf('.')).length, lessThanOrEqualTo(16));
    });

    test('the result never contains path separators', () {
      for (final raw in ['a/b', r'a\b', '../x', 'x/..', r'..\..\x']) {
        expect(safeFileName(raw), isNot(contains('/')));
        expect(safeFileName(raw), isNot(contains(r'\')));
      }
    });
  });
}
