import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:sagip_shared/sagip_shared.dart';

import 'browser/browser.dart';

// Providers for the resident web form (W1 to W3). It is a second entry
// point of this package (lib/main_webform.dart) with its own, much smaller
// set of repositories: sign-in by mobile number and crowd reports. It never
// sends an SOS (FR15).

Never _missing(String name) => throw UnimplementedError(
  '$name is not configured. Override it in main_webform.dart.',
);

final webAuthProvider = Provider<AuthRepository>(
  (ref) => _missing('AuthRepository'),
);
final webAccountsProvider = Provider<ResidentAccountRepository>(
  (ref) => _missing('ResidentAccountRepository'),
);
final webReportsProvider = Provider<WebReportRepository>(
  (ref) => _missing('WebReportRepository'),
);

final webClientConfigRepositoryProvider = Provider<ClientConfigRepository>(
  (ref) => const StaticClientConfigRepository(),
);

final browserLocationProvider = Provider<BrowserLocation>(
  (ref) => createBrowserLocation(),
);
final draftStoreProvider = Provider<DraftStore>((ref) => createDraftStore());
final browserConnectionProvider = Provider<BrowserConnection>(
  (ref) => createBrowserConnection(),
);

/// Only set when running on sample data; W1 then shows the demo number and
/// code.
final webMockBackendProvider = Provider<MockMobileBackend?>((ref) => null);

/// Whether map tiles load from the network. Tests turn this off.
final webMapTilesProvider = Provider<bool>((ref) => true);

/// Values set when the web form is built (`--dart-define`).
@immutable
class WebFormConfig {
  const WebFormConfig({
    this.hotline = '',
    this.appDownloadUrl = '',
    this.allowRegistration = true,
  });

  const WebFormConfig.fromEnvironment()
    : hotline = const String.fromEnvironment('MDRRMD_HOTLINE'),
      appDownloadUrl = const String.fromEnvironment('APP_DOWNLOAD_URL'),
      allowRegistration = const bool.fromEnvironment(
        'WEBFORM_REGISTRATION',
        defaultValue: true,
      );

  /// The MDRRMD hotline fixed at build time. Usually empty: the form then
  /// shows the one an administrator set on A3 ([webHotlineProvider]).
  final String hotline;

  /// Where to get the app; empty hides the link.
  final String appDownloadUrl;

  /// Creating an account on the web form (plan Q13, not decided yet; the
  /// plan suggests allowing it). Off: only numbers that already have an
  /// account can sign in.
  final bool allowRegistration;
}

final webConfigProvider = Provider<WebFormConfig>(
  (ref) => const WebFormConfig.fromEnvironment(),
);

/// The hotline an administrator set on A3. A failed fetch leaves it empty,
/// and the notice then says "call MDRRMD" without a number.
final webClientConfigProvider = FutureProvider<ClientConfig>((ref) async {
  try {
    return await ref.watch(webClientConfigRepositoryProvider).fetch();
  } on Object {
    return const ClientConfig();
  }
});

/// The hotline the notice shows: the build's value when it has one, else
/// the one set on A3.
final webHotlineProvider = Provider<String>((ref) {
  final built = ref.watch(webConfigProvider).hotline;
  return built.isNotEmpty
      ? built
      : ref.watch(webClientConfigProvider).value?.hotline ?? '';
});

List<Override> webMockOverrides(
  MockMobileBackend backend, {
  bool demoTools = true,
}) => [
  webMockBackendProvider.overrideWithValue(demoTools ? backend : null),
  webAuthProvider.overrideWithValue(MockMobileAuthRepository(backend)),
  webAccountsProvider.overrideWithValue(MockResidentAccountRepository(backend)),
  webReportsProvider.overrideWithValue(MockWebReportRepository(backend)),
];

List<Override> webSupabaseOverrides(SupabaseWebFormBackend backend) => [
  webAuthProvider.overrideWithValue(backend.accounts),
  webAccountsProvider.overrideWithValue(backend.accounts),
  webReportsProvider.overrideWithValue(backend.reports),
  webClientConfigRepositoryProvider.overrideWithValue(backend.config),
];

// ---------------------------------------------------------------- live data

final webUserProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(webAuthProvider).watchUser(),
);

/// The signed-in resident's id, or null. Only residents use the web form.
final webUserIdProvider = Provider<String?>((ref) {
  final user = ref.watch(webUserProvider).value;
  return user?.role == UserRole.resident ? user!.id : null;
});

/// Unknown counts as online so the first frame shows no banner.
final webOnlineProvider = StreamProvider<bool>(
  (ref) => ref.watch(browserConnectionProvider).watch(),
);
final webIsOnlineProvider = Provider<bool>(
  (ref) => ref.watch(webOnlineProvider).value ?? true,
);

/// Streams restart when the account changes and wait while signed out, so
/// one account's reports never stay on screen for the next.
Stream<T> _forAccount<T>(Ref ref, Stream<T> Function() open) =>
    ref.watch(webUserIdProvider) == null ? const Stream.empty() : open();

final myWebReportsProvider = StreamProvider<List<HazardReport>>(
  (ref) => _forAccount(ref, () => ref.watch(webReportsProvider).watchMine()),
);

final reportQuotaProvider = StreamProvider<ReportQuota>(
  (ref) => _forAccount(ref, () => ref.watch(webReportsProvider).watchQuota()),
);
