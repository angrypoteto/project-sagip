import 'dart:js_interop';

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
