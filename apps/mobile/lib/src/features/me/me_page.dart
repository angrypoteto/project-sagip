import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// S7, first version: who is signed in, sign out, and (on sample data) the
/// demo switches for signal and GPS. Settings and the privacy links come
/// in a later step.
class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final user = ref.watch(currentUserProvider).value;
    final profile = ref.watch(myProfileProvider).value;
    final backend = ref.watch(mockBackendProvider);

    return ListView(
      padding: const EdgeInsets.all(SagipSpace.xl),
      children: [
        Text(l10n.meTitle, style: text.headlineSmall),
        const SizedBox(height: SagipSpace.xl),
        if (user != null) ...[
          Text(user.displayName, style: text.titleLarge),
          const SizedBox(height: SagipSpace.xs),
          Text(
            user.role == UserRole.resident
                ? l10n.roleResident
                : l10n.roleResponder,
            style: text.bodyMedium!.copyWith(color: p.textSecondary),
          ),
          if (profile != null)
            Text(
              l10n.place(profile.barangay, profile.district),
              style: text.bodyMedium!.copyWith(color: p.textSecondary),
            ),
        ],
        if (backend != null) ...[
          const SizedBox(height: SagipSpace.x3),
          _DemoTools(backend: backend),
        ],
        const SizedBox(height: SagipSpace.x3),
        OutlinedButton.icon(
          onPressed: () => ref.read(authRepositoryProvider).signOut(),
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
            if (ref.watch(currentUserProvider).value?.role ==
                UserRole.responder) ...[
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
