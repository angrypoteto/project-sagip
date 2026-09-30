import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';

/// S2 Welcome and permissions: three short steps, each explaining why
/// before asking. Every step can be skipped; SOS works either way.
class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key});

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _Step {
  const _Step(this.icon, this.title, this.body, this.permissions);

  final IconData icon;
  final String title;
  final String body;
  final List<AppPermission> permissions;
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  var _index = 0;

  List<_Step> _steps(AppLocalizations l10n) => [
    _Step(
      Symbols.location_on_rounded,
      l10n.welcomeStep1Title,
      l10n.welcomeStep1Body,
      const [AppPermission.location],
    ),
    _Step(
      Symbols.notifications_rounded,
      l10n.welcomeStep2Title,
      l10n.welcomeStep2Body,
      const [AppPermission.notifications],
    ),
    _Step(
      Symbols.cell_tower_rounded,
      l10n.welcomeStep3Title,
      l10n.welcomeStep3Body,
      const [AppPermission.sms, AppPermission.nearbyDevices],
    ),
  ];

  void _next(int total) {
    if (_index + 1 < total) {
      setState(() => _index++);
    } else {
      ref.read(welcomeSeenProvider.notifier).markSeen();
      context.go(Routes.signIn);
    }
  }

  Future<void> _allow(_Step step) async {
    final service = ref.read(permissionServiceProvider);
    for (final p in step.permissions) {
      await service.request(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final steps = _steps(l10n);
    final step = steps[_index];
    final states = ref.watch(permissionsProvider).value ?? const {};
    final stepStates = [
      for (final perm in step.permissions)
        states[perm] ?? PermissionState.notAsked,
    ];
    final granted = stepStates.every((s) => s == PermissionState.granted);
    final blocked = stepStates.any(
      (s) => s == PermissionState.permanentlyDenied,
    );
    final refused = stepStates.any(
      (s) =>
          s == PermissionState.denied || s == PermissionState.permanentlyDenied,
    );
    final last = _index == steps.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SagipSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.welcomeStepOf(_index + 1, steps.length),
                style: text.labelLarge!.copyWith(color: p.textSecondary),
              ),
              const Spacer(),
              Icon(step.icon, size: 64, color: p.info.text),
              const SizedBox(height: SagipSpace.xl),
              Text(step.title, style: text.headlineSmall),
              const SizedBox(height: SagipSpace.md),
              Text(step.body, style: text.bodyLarge),
              const SizedBox(height: SagipSpace.xl),
              if (granted)
                Row(
                  children: [
                    Icon(
                      Symbols.check_circle_rounded,
                      color: p.success.text,
                      fill: 1,
                    ),
                    const SizedBox(width: SagipSpace.sm),
                    Text(
                      l10n.allowed,
                      style: text.titleSmall!.copyWith(color: p.success.text),
                    ),
                  ],
                )
              else if (refused) ...[
                Text(
                  l10n.notAllowed,
                  style: text.bodyMedium!.copyWith(color: p.warning.text),
                ),
                if (blocked)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          ref.read(permissionServiceProvider).openSettings(),
                      icon: const Icon(Symbols.settings_rounded),
                      label: Text(l10n.openSettings),
                    ),
                  ),
              ],
              const Spacer(),
              SizedBox(
                height: 56,
                child: granted || blocked
                    ? FilledButton(
                        onPressed: () => _next(steps.length),
                        child: Text(last ? l10n.getStarted : l10n.next),
                      )
                    : FilledButton(
                        onPressed: () => _allow(step),
                        child: Text(l10n.allow),
                      ),
              ),
              const SizedBox(height: SagipSpace.sm),
              // Same height with or without Skip, so the main button
              // stays under the thumb after Allow.
              SizedBox(
                height: 48,
                child: !granted && !blocked
                    ? TextButton(
                        onPressed: () => _next(steps.length),
                        child: Text(l10n.skip),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
