import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// What a photo belongs to (2026-10-19).
enum PhotoKind { sos, report }

/// A photo on an incident as the dashboard shows it: the SOS's, or one
/// from a crowd report in its cluster. [url] is a short-lived link.
@immutable
class IncidentPhoto {
  const IncidentPhoto({
    required this.id,
    required this.kind,
    required this.url,
    required this.uploadedAt,
  });

  final String id;
  final PhotoKind kind;
  final String url;
  final DateTime uploadedAt;

  @override
  bool operator ==(Object other) =>
      other is IncidentPhoto &&
      other.id == id &&
      other.kind == kind &&
      other.url == url &&
      other.uploadedAt == uploadedAt;

  @override
  int get hashCode => Object.hash(id, kind, url, uploadedAt);
}

/// The longest side of a photo sent to MDRRMD, in pixels.
const photoMaxSide = 1280;

/// At most this many photos on one SOS or report (the server's limit).
const photosPerRecord = 3;

/// Gets a photo ready to send: turned upright, at most [photoMaxSide]
/// pixels on its longest side, saved again as a JPEG with no metadata (no
/// location, no camera details; RA 10173). Null when it is not an image.
Uint8List? preparePhoto(Uint8List raw, {int quality = 70}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(raw);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) return null;
  var upright = img.bakeOrientation(decoded);
  final longest = upright.width > upright.height
      ? upright.width
      : upright.height;
  if (longest > photoMaxSide) {
    upright = upright.width >= upright.height
        ? img.copyResize(upright, width: photoMaxSide)
        : img.copyResize(upright, height: photoMaxSide);
  }
  upright.exif = img.ExifData();
  return img.encodeJpg(upright, quality: quality);
}
