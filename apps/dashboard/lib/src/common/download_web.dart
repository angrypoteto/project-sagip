import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Not used on the web; kept so both versions have the same names.
({String name, String text})? lastDownload;

void downloadText(String name, String text, {String type = 'text/csv'}) {
  final blob = web.Blob(
    [text.toJS].toJS,
    web.BlobPropertyBag(type: '$type;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  anchor.click();
  web.URL.revokeObjectURL(url);
  lastDownload = (name: name, text: text);
}

/// Not used on the web; kept so both versions have the same names.
({String name, List<int> bytes})? lastBinaryDownload;

/// Saves a binary file (A6: the report PDF).
void downloadBytes(
  String name,
  List<int> bytes, {
  String type = 'application/pdf',
}) {
  final blob = web.Blob(
    [Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: type),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
