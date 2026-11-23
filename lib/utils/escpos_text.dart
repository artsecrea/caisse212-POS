/// Turns ESC/POS printer bytes back into plain text — what the paper would
/// read, minus fonts, sizes and images.
///
/// Used to EXPORT a report from the exact bytes the printer would receive,
/// rather than from a second text layout that would drift from the paper.
///
/// Covers the commands `esc_pos_utils_plus` emits. Column positions (ESC $,
/// in dots) become spaces at [dotsPerChar] dots per character — 12 for font A
/// on both 58 mm (384 dots / 32 chars) and 80 mm (576 / 48) heads. Images and
/// barcodes are skipped by their declared length. Text bytes are read as
/// Latin-1, which is what the code tables the POS uses agree on for the
/// characters it prints (accents are already folded by the printing service).
library;

String escPosToText(List<int> bytes, {int dotsPerChar = 12}) {
  final out = StringBuffer();
  final line = StringBuffer();
  var i = 0;

  int at(int k) => k < bytes.length ? bytes[k] : 0;

  void endLine() {
    out.writeln(line.toString().trimRight());
    line.clear();
  }

  while (i < bytes.length) {
    final b = bytes[i];
    if (b == 0x0A) {
      endLine();
      i++;
    } else if (b == 0x0D || b == 0x00) {
      i++;
    } else if (b == 0x1B) {
      // ESC
      final c = at(i + 1);
      switch (c) {
        case 0x40: // @ init
        case 0x32: // 2 default line spacing
          i += 2;
        case 0x24: // $ nL nH absolute position (dots)
          final dots = at(i + 2) + at(i + 3) * 256;
          final col = dots ~/ dotsPerChar;
          final len = line.length;
          if (col > len) {
            line.write(' ' * (col - len));
          } else if (len > 0 && !line.toString().endsWith(' ')) {
            line.write(' ');
          }
          i += 4;
        case 0x64: // d n feed n lines
          final n = at(i + 2);
          endLine();
          for (var k = 1; k < n; k++) {
            out.writeln();
          }
          i += 3;
        case 0x2A: // * m nL nH data — column-format image
          final m = at(i + 2);
          final n = at(i + 3) + at(i + 4) * 256;
          final perCol = (m == 32 || m == 33) ? 3 : 1;
          i += 5 + n * perCol;
        case 0x70: // p m t1 t2 — drawer kick
          i += 5;
        case 0x42: // B n t — beeper
          i += 4;
        default: // every other ESC command takes one parameter byte
          i += 3;
      }
    } else if (b == 0x1D) {
      // GS
      final c = at(i + 1);
      switch (c) {
        case 0x56: // V m [n] — cut
          final m = at(i + 2);
          i += (m == 65 || m == 66) ? 4 : 3;
        case 0x76: // v 0 m xL xH yL yH data — raster image
          final w = at(i + 4) + at(i + 5) * 256;
          final h = at(i + 6) + at(i + 7) * 256;
          i += 8 + w * h;
        case 0x28: // ( X pL pH data — graphics / QR / control
          final len = at(i + 3) + at(i + 4) * 256;
          i += 5 + len;
        case 0x6B: // k m ... — barcode
          final m = at(i + 2);
          if (m >= 65) {
            i += 4 + at(i + 3);
          } else {
            var k = i + 3;
            while (k < bytes.length && bytes[k] != 0) {
              k++;
            }
            i = k + 1;
          }
        case 0x4C: // L nL nH — left margin
        case 0x57: // W nL nH — print area width
          i += 4;
        default: // ! n, B n, h n, w n, f n, H n …
          i += 3;
      }
    } else if (b == 0x1C) {
      // FS: & and . (kanji on/off) take none; the rest one.
      final c = at(i + 1);
      i += (c == 0x26 || c == 0x2E) ? 2 : 3;
    } else if (b < 0x20) {
      i++; // other control bytes (HT, FF…) carry no text
    } else {
      line.writeCharCode(b);
      i++;
    }
  }
  if (line.isNotEmpty) endLine();

  // Collapse runs of blank lines the feeds produce.
  return out
      .toString()
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trimRight();
}
