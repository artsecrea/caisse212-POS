import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:caisse212/utils/logo_filter.dart';

img.Image _solid(int w, int h, int r, int g, int b, [int a = 255]) {
  final i = img.Image(width: w, height: h, numChannels: 4);
  img.fill(i, color: img.ColorRgba8(r, g, b, a));
  return i;
}

Set<int> _levels(img.Image i) => {
      for (final p in i) ...[p.r.toInt(), p.g.toInt(), p.b.toInt()]
    };

void main() {
  test('black & white leaves only pure black and pure white', () {
    final src = _solid(8, 8, 200, 30, 30); // a red that a printer muddles
    src.setPixelRgba(0, 0, 250, 250, 250, 255);
    final out = applyLogoFilter(src, LogoFilter.blackWhite, 128);
    expect(_levels(out), {0, 255});
    expect(out.getPixel(0, 0).r, 255);
    expect(out.getPixel(1, 1).r, 0); // luminance ~84 < 128
  });

  test('the threshold moves the cut', () {
    final grey = _solid(2, 2, 150, 150, 150);
    expect(applyLogoFilter(grey, LogoFilter.blackWhite, 128).getPixel(0, 0).r,
        255);
    expect(applyLogoFilter(grey, LogoFilter.blackWhite, 200).getPixel(0, 0).r,
        0);
  });

  test('transparent pixels are paper, not ink', () {
    final clear = _solid(4, 4, 0, 0, 0, 0);
    final out = applyLogoFilter(clear, LogoFilter.blackWhite, 128);
    expect(_levels(out), {255});
  });

  test('dithering a mid grey gives roughly half the dots', () {
    final grey = _solid(40, 40, 128, 128, 128);
    final out = applyLogoFilter(grey, LogoFilter.dither, 128);
    expect(_levels(out), {0, 255});
    final black = out.where((p) => p.r == 0).length;
    expect(black / (40 * 40), closeTo(0.5, 0.05));
  });

  test('none returns the image untouched', () {
    final src = _solid(2, 2, 10, 20, 30);
    expect(identical(applyLogoFilter(src, LogoFilter.none, 128), src), isTrue);
  });
}
