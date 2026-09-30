import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../common/privacy_notice.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

/// S7 Me: profile, settings, privacy, and sign out. On sample data it also
/// has the demo switches for signal, GPS, and assignments.
class MePage extends ConsumerWidget {
  const MePage({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final waiting = ref.read(pendingQueueProvider).value?.length ?? 0;
    if (waiting > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.signOutTitle),
          content: Text(l10n.signOutWaiting(waiting)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.signOut),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await ref.read(authRepositoryProvider).signOut();
  }

  Future<void> _requestDeletion(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.requestDeletionTitle),
        content: Text(l10n.requestDeletionBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.requestDeletionConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(residentAccountRepositoryProvider).requestDataDeletion();
      messenger.showSnackBar(SnackBar(content: Text(l10n.requestDeletionSent)));
    } on ActionRejected {
      messenger.showSnackBar(SnackBar(content: Text(l10n.phoneOffline)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final user = ref.watch(currentUserProvider).value;
    final profile = ref.watch(myProfileProvider).value;
    final backend = ref.watch(mockBackendProvider);
    final resident = user?.role == UserRole.resident;
    final theme = ref.watch(themeModeProvider);

    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: SagipSpace.x3, bottom: SagipSpace.sm),
      child: Text(
        title,
        style: text.labelLarge!.copyWith(color: p.textSecondary),
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(SagipSpace.xl),
      children: [
        Text(l10n.meTitle, style: text.headlineSmall),
        const SizedBox(height: SagipSpace.xl),
        if (user != null) ...[
          Text(user.displayName, style: text.titleLarge),
          const SizedBox(height: SagipSpace.xs),
          Text(
            resident ? l10n.roleResident : l10n.roleResponder,
            style: text.bodyMedium!.copyWith(color: p.textSecondary),
          ),
          if (profile != null) ...[
            Text(
              l10n.place(profile.barangay, profile.district),
              style: text.bodyMedium!.copyWith(color: p.textSecondary),
            ),
            Text(
              profile.contactNumber,
              style: text.bodyMedium!.copyWith(color: p.textSecondary),
            ),
          ],
        ],
        if (resident) ...[
          const SizedBox(height: SagipSpace.lg),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Symbols.history_rounded),
            title: Text(l10n.myActivity),
            trailing: const Icon(Symbols.chevron_right_rounded),
            onTap: () => context.push(Routes.activity),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Symbols.accessible_rounded),
            title: Text(l10n.vulnerabilityProfile),
            trailing: const Icon(Symbols.chevron_right_rounded),
            onTap: () => context.push(Routes.vulnerability),
          ),
        ],
        section(l10n.settings),
        Text(l10n.theme, style: text.titleSmall),
        const SizedBox(height: SagipSpace.sm),
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(
              value: ThemeMode.system,
              label: Text(l10n.themeSystem),
            ),
            ButtonSegment(value: ThemeMode.light, label: Text(l10n.themeLight)),
            ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark)),
          ],
          selected: {theme},
          showSelectedIcon: false,
          onSelectionChanged: (s) =>
              ref.read(themeModeProvider.notifier).set(s.single),
        ),
        const SizedBox(height: SagipSpace.md),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Symbols.language_rounded),
          title: Text(l10n.language),
          subtitle: Text('${l10n.languageEnglish} · ${l10n.languageSoon}'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Symbols.notifications_active_rounded),
          title: Text(l10n.testNotification),
          onTap: () => ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l10n.testNotificationSent))),
        ),
        section(l10n.privacy),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Symbols.privacy_tip_rounded),
          title: Text(l10n.privacyNotice),
          onTap: () => showPrivacyNotice(context),
        ),
        if (resident)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Symbols.delete_rounded, color: p.critical.text),
            title: Text(
              l10n.requestDeletion,
              style: TextStyle(color: p.critical.text),
            ),
            onTap: () => _requestDeletion(context, ref),
          ),
        if (backend != null) ...[
          const SizedBox(height: SagipSpace.x3),
          _DemoTools(backend: backend),
        ],
        const SizedBox(height: SagipSpace.x3),
        OutlinedButton.icon(
          onPressed: () => _signOut(context, ref),
          icon: const Icon(Symbols.logout_rounded),
          label: Text(l10n.signOut),
        ),
      ],
    );
  }
}

class _DemoTools extends ConsumerWidget {
  const _DemoTools({required this.backend});

  final MockMobileBackend backend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final signal = ref.watch(signalProvider).value ?? SignalState.internet;
    final gpsOn = ref.watch(locationProvider).value?.gpsOn ?? true;
    final responder =
        ref.watch(currentUserProvider).value?.role == UserRole.responder;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: p.hairlineStrong),
        borderRadius: BorderRadius.circular(SagipRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.demoTitle, style: text.titleMedium),
            Text(
              l10n.demoNote,
              style: text.bodySmall!.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: SagipSpace.lg),
            Text(l10n.demoSignal, style: text.labelLarge),
            const SizedBox(height: SagipSpace.sm),
            SegmentedButton<SignalState>(
              segments: [
                for (final s in SignalState.values)
                  ButtonSegment(value: s, label: Text(l10n.signal(s))),
              ],
              selected: {signal},
              showSelectedIcon: false,
              onSelectionChanged: (s) => backend.setSignal(s.single),
            ),
            const SizedBox(height: SagipSpace.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.demoGps),
              value: gpsOn,
              onChanged: (on) => backend.setGps(on: on),
            ),
            if (responder) ...[
              const SizedBox(height: SagipSpace.sm),
              OutlinedButton(
                onPressed: backend.sendOfferNow,
                child: Text(l10n.demoOffer),
              ),
              const SizedBox(height: SagipSpace.sm),
              OutlinedButton(
                onPressed: backend.dispatcherCloses,
                child: Text(l10n.demoClose),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
