/// This app's build number: the `+N` of `version` in pubspec.yaml (a test
/// checks they match). Raise both with every release; the server's
/// `app.min_build` (A3) can then require it.
const appBuild = 4;

/// Where a resident or responder downloads the newest app.
const appDownloadUrl = 'https://sagip.me/download/sagip.apk';
