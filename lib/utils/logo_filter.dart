import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// How the logo is turned into the 1-bit picture a thermal printer can print.
enum LogoFilter {
  /// Left to the printer library's own conversion. A colour or grey logo
  /// often comes out as a solid black block or fades out entirely.
  none,

  /// Every pixel goes pure black or pure white at [kDefaultLogoThreshold].
  /// Best for flat logos: text, shapes, a few solid colours.
  blackWhite,

  /// Floyd–Steinberg dithering: greys become dot patterns. Best for photos
  /// and gradients, which a hard threshold flattens.
  dither,
}

/// Midpoint of the 0..255 luminance scale. Lower prints lighter (fewer
/// pixels count as black), higher prints darker.
const int kDefaultLogoThreshold = 128;

/// Turn an opaque image into pure black and white, per [filter].
///
/// Returns a new RGBA image (the printer library rasterises 4-channel
/// images) holding only #000 and #FFF, so the printer's own threshold has
/// nothing left to decide and the paper matches the preview.
img.Image applyLogoFilter(img.Image src, LogoFilter filter, int threshold) {
  if (filter == LogoFilter.none) return src;
  final t = threshold.clamp(1, 254);
  final w = src.width;
  final h = src.height;

  // Luminance per pixel, as doubles so dithering can carry error forward.
  // Alpha is folded onto white: a transparent pixel is paper, not ink.
  final lum = Float64List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = src.getPixel(x, y);
      final a = p.aNormalized;
      final l = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      lum[y * w + x] = l * a + 255 * (1 - a);
    }
  }

  final out = img.Image(width: w, height: h, numChannels: 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final old = lum[i];
      final black = old < t;
      final v = black ? 0 : 255;
      out.setPixelRgba(x, y, v, v, v, 255);
      if (filter == LogoFilter.dither) {
        final err = old - v;
        if (x + 1 < w) lum[i + 1] += err * 7 / 16;
        if (y + 1 < h) {
          if (x > 0) lum[i + w - 1] += err * 3 / 16;
          lum[i + w] += err * 5 / 16;
          if (x + 1 < w) lum[i + w + 1] += err * 1 / 16;
        }
      }
    }
  }
  return out;
}

/// The whole picked image as the printer will see it, for the editor's
/// preview: shrunk to [maxWidth], flattened on white, then filtered.
///
/// Uncropped on purpose — the editor draws its crop box over the full image.
Uint8List? logoPreviewPng(
  img.Image decoded,
  LogoFilter filter,
  int threshold, {
  int maxWidth = 576,
}) {
  var src = decoded;
  if (src.width > maxWidth) src = img.copyResize(src, width: maxWidth);
  final flat = img.Image(width: src.width, height: src.height, numChannels: 4);
  img.fill(flat, color: img.ColorRgba8(255, 255, 255, 255));
  img.compositeImage(flat, src);
  return img.encodePng(applyLogoFilter(flat, filter, threshold));
}
