/// The last file "saved" off the web (widget tests read it).
({String name, String text})? lastDownload;

void downloadText(String name, String text, {String type = 'text/csv'}) {
  lastDownload = (name: name, text: text);
}
