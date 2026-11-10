import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../board/map_parts.dart';

/// D1 Staff sign in. Redirects happen in the router once the user changes.
class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The eye in the password field shows what was typed (2026-11-10).
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Where the seal is, for the flight after signing in.
  final _sealKey = GlobalKey();

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    // Readied now: once signed in, the router replaces this page.
    final flight = SealFlightLauncher(context, seal: _sealKey);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(email: _email.text, password: _password.text);
      // Accepted: the seal alone floats, then flies forward and fades,
      // over the board as it opens (Joshua, 2026-11-10).
      flight.play();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = l10n.authFailure(e.reason));
    } catch (_) {
      if (mounted) setState(() => _error = l10n.errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final isMock = ref.watch(mockBackendProvider) != null;
    String? required(String? v) =>
        (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null;
    // A laptop at 150% scaling leaves about 500 px of height: tighter
    // there, so the whole card shows without scrolling (2026-11-11).
    final short = MediaQuery.sizeOf(context).height < 640;
    final gap = short ? SagipSpace.lg : SagipSpace.xxl;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _ManilaBackdrop()),
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(short ? SagipSpace.md : SagipSpace.xxl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(
                      short ? SagipSpace.xl : SagipSpace.x3,
                    ),
                    child: Form(
                      key: _form,
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // MDRRMD's seal above the name, both centered
                            // (Joshua, 2026-11-10).
                            // It eases in, and pulses with a ring while signing
                            // in (Joshua, 2026-11-10).
                            Center(
                              child: SealEntrance(
                                key: _sealKey,
                                busy: _busy,
                                size: short ? 48 : 72,
                              ),
                            ),
                            const SizedBox(height: SagipSpace.md),
                            Text(
                              l10n.brandName,
                              style: text.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                            // The city's motto (Joshua, 2026-11-10).
                            Text(
                              l10n.cityMotto,
                              key: const ValueKey('city-motto'),
                              style: text.labelMedium!.copyWith(
                                color: p.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: gap),
                            // Centered under the seal (Joshua, 2026-11-10).
                            Text(
                              l10n.signInTitle,
                              style: text.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: SagipSpace.sm),
                            Text(
                              l10n.signInSubtitle,
                              style: text.bodyMedium!.copyWith(
                                color: p.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: gap),
                            TextFormField(
                              controller: _email,
                              // Ready to type on open (2026-11-11).
                              autofocus: true,
                              decoration: InputDecoration(
                                labelText: l10n.emailLabel,
                              ),
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              validator: required,
                            ),
                            const SizedBox(height: SagipSpace.lg),
                            TextFormField(
                              controller: _password,
                              decoration: InputDecoration(
                                labelText: l10n.passwordLabel,
                                suffixIcon: IconButton(
                                  key: const ValueKey('show-password'),
                                  icon: Icon(
                                    _showPassword
                                        ? Symbols.visibility_off_rounded
                                        : Symbols.visibility_rounded,
                                  ),
                                  tooltip: _showPassword
                                      ? l10n.hidePassword
                                      : l10n.showPassword,
                                  onPressed: () => setState(
                                    () => _showPassword = !_showPassword,
                                  ),
                                ),
                              ),
                              obscureText: !_showPassword,
                              autofillHints: const [AutofillHints.password],
                              onFieldSubmitted: (_) => _submit(),
                              validator: required,
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: SagipSpace.lg),
                              Text(
                                _error!,
                                style: text.bodyMedium!.copyWith(
                                  color: p.critical.text,
                                ),
                              ),
                            ],
                            SizedBox(height: gap),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: Text(
                                _busy ? l10n.signingIn : l10n.signInButton,
                              ),
                            ),
                            const SizedBox(height: SagipSpace.lg),
                            Text(
                              l10n.forgotPassword,
                              style: text.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                            if (isMock) ...[
                              const SizedBox(height: SagipSpace.lg),
                              Container(
                                padding: const EdgeInsets.all(SagipSpace.md),
                                decoration: BoxDecoration(
                                  color: p.panelRaised,
                                  borderRadius: BorderRadius.circular(
                                    SagipRadius.control,
                                  ),
                                ),
                                child: SelectableText(
                                  l10n.demoAccountsHint(MockSeed.demoPassword),
                                  style: text.bodySmall,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Behind the sign-in card: Manila, its barangays, dimmed so the card
/// stays the thing to read (Joshua, 2026-11-10: "a picture of Manila").
/// Not a map to use: it does not move.
class _ManilaBackdrop extends StatelessWidget {
  const _ManilaBackdrop();

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ManilaZoom(
              builder: (context, minZoom) => FlutterMap(
                key: const ValueKey('sign-in-backdrop'),
                options: MapOptions(
                  backgroundColor: mapBackground(context),
                  initialCenter: manilaCenter,
                  initialZoom: minZoom,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: const [SagipBaseMap(), BarangayBoundaries()],
              ),
            ),
            // A wash of the page color, darker at the edges.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.1,
                  colors: [
                    p.canvas.withValues(alpha: 0.55),
                    p.canvas.withValues(alpha: 0.9),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
