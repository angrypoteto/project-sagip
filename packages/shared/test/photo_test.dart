import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sagip_shared/sagip_shared.dart';

/// Photos are made small and carry nothing about where they were taken
/// (2026-10-19, RA 10173).
void main() {
  Uint8List cameraShot({required int w, required int h, int orientation = 1}) {
    final shot = img.Image(width: w, height: h);
    img.fill(shot, color: img.ColorRgb8(200, 30, 30));
    // The top-left corner is white, to see which way it was turned.
    img.fillRect(
      shot,
      x1: 0,
      y1: 0,
      x2: 9,
      y2: 9,
      color: img.ColorRgb8(255, 255, 255),
    );
    shot.exif.imageIfd['Orientation'] = orientation;
    shot.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(14, 1);
    shot.exif.imageIfd['Make'] = 'PhoneMaker';
    return img.encodeJpg(shot);
  }

  test('shrunk to 1280 px on its longest side, no metadata', () {
    final raw = cameraShot(w: 3000, h: 2000);
    expect(img.decodeJpgExif(raw)!.gpsIfd.isEmpty, isFalse);
    final ready = preparePhoto(raw)!;
    final out = img.decodeJpg(ready)!;
    expect(out.width, photoMaxSide);
    expect(out.height, (2000 * photoMaxSide / 3000).round());
    final exif = img.decodeJpgExif(ready);
    expect(
      exif == null || (exif.gpsIfd.isEmpty && exif.imageIfd.isEmpty),
      isTrue,
    );
    expect(ready.length, lessThan(raw.length));
  });

  test('a photo taken with the phone turned is stored upright', () {
    // Orientation 6: the camera saved it turned; viewers rotate it 90°.
    final ready = preparePhoto(cameraShot(w: 400, h: 300, orientation: 6))!;
    final out = img.decodeJpg(ready)!;
    expect((out.width, out.height), (300, 400));
  });

  test('a small photo keeps its size; not an image is refused', () {
    final out = img.decodeJpg(preparePhoto(cameraShot(w: 800, h: 600))!)!;
    expect((out.width, out.height), (800, 600));
    expect(preparePhoto(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
