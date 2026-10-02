/// The last file "saved" off the web (widget tests read it).
({String name, String text})? lastDownload;

void downloadText(String name, String text, {String type = 'text/csv'}) {
  lastDownload = (name: name, text: text);
}

/// The last binary file "saved" (widget tests read it).
({String name, List<int> bytes})? lastBinaryDownload;

void downloadBytes(
  String name,
  List<int> bytes, {
  String type = 'application/pdf',
}) {
  lastBinaryDownload = (name: name, bytes: bytes);
}
