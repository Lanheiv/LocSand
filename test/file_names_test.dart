import 'package:flutter_test/flutter_test.dart';
import 'package:locsand/src/helpers/file_names.dart';

void main() {
  test('strips path traversal and separators', () {
    expect(safeFileName('../../etc/passwd'), 'passwd');
    expect(safeFileName(r'..\..\evil.exe'), 'evil.exe');
    expect(safeFileName('/abs/path/file.txt'), 'file.txt');
  });

  test('falls back for empty or dot names', () {
    expect(safeFileName(''), 'received_file');
    expect(safeFileName('..'), 'received_file');
    expect(safeFileName('...'), 'received_file');
    expect(safeFileName('///'), 'received_file');
  });

  test('replaces characters that are invalid on Windows', () {
    expect(safeFileName('a<b>c:d"e|f?g*h.txt'), 'a_b_c_d_e_f_g_h.txt');
    expect(safeFileName('a\u0000b.txt'), 'a_b.txt');
  });

  test('avoids Windows reserved device names', () {
    expect(safeFileName('CON'), '_CON');
    expect(safeFileName('nul.txt'), '_nul.txt');
    expect(safeFileName('COM1.log'), '_COM1.log');
    expect(safeFileName('console.txt'), 'console.txt');
  });

  test('strips trailing dots and spaces', () {
    expect(safeFileName('report.pdf. . '), 'report.pdf');
  });

  test('bounds the length and keeps the extension', () {
    final name = safeFileName('${'a' * 500}.pdf');
    expect(name.length, lessThanOrEqualTo(120));
    expect(name.endsWith('.pdf'), isTrue);
  });
}
