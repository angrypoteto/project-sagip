/// The app routes "opened" in a new window (widget tests read it).
final openedWindows = <String>[];

/// Opens [route] (for example `/wall`) in a window of its own.
void openInNewWindow(String route) => openedWindows.add(route);

/// Whether the page fills the screen (widget tests set it by toggling).
bool isFullScreen = false;

/// Fills the screen with the page, or goes back to the window.
Future<void> toggleFullScreen() async => isFullScreen = !isFullScreen;

/// Emits whenever full screen starts or ends (also with Esc).
Stream<void> get fullScreenChanges => const Stream.empty();
