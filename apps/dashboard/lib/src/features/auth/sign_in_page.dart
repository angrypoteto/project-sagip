import 'dart:math' as math;

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
    // Taken now: once signed in, the router replaces this page.
    final overlay = Overlay.of(context, rootOverlay: true);
    final still = MediaQuery.of(context).disableAnimations;
    final box = _sealKey.currentContext?.findRenderObject() as RenderBox?;
    final seal = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final canvas = SagipPalette.of(context).canvas;
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
      if (!still && seal != null) {
        late final OverlayEntry entry;
        entry = OverlayEntry(
          builder: (_) => SealFlight(
            from: seal,
            background: canvas,
            onDone: () => entry.remove(),
          ),
        );
        overlay.insert(entry);
      }
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

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _ManilaBackdrop()),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(SagipSpace.xxl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(SagipSpace.x3),
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
                              child: KeyedSubtree(
                                key: _sealKey,
                                child: _AnimatedSeal(busy: _busy),
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
                            const SizedBox(height: SagipSpace.xxl),
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
                            const SizedBox(height: SagipSpace.xxl),
                            TextFormField(
                              controller: _email,
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
                            const SizedBox(height: SagipSpace.xxl),
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

/// MDRRMD's seal on the sign-in card: it eases in when the page opens, and
/// while signing in it breathes inside a turning ring. Still when the
/// device asks for less motion.
class _AnimatedSeal extends StatefulWidget {
  const _AnimatedSeal({required this.busy});

  final bool busy;

  @override
  State<_AnimatedSeal> createState() => _AnimatedSealState();
}

class _AnimatedSealState extends State<_AnimatedSeal>
    with TickerProviderStateMixin {
  static const _size = 72.0;
  static const _ring = 92.0;

  late final _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool get _still => MediaQuery.of(context).disableAnimations;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still) {
      _enter.value = 1;
    } else if (_enter.status == AnimationStatus.dismissed) {
      _enter.forward();
    }
  }

  @override
  void didUpdateWidget(_AnimatedSeal old) {
    super.didUpdateWidget(old);
    if (widget.busy == old.busy) return;
    if (widget.busy && !_still) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.animateTo(0, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final enter = CurvedAnimation(parent: _enter, curve: Curves.easeOutBack);
    final pulse = CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);
    return SizedBox.square(
      key: const ValueKey('sign-in-seal'),
      dimension: _ring,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.busy)
            SizedBox.square(
              dimension: _ring,
              child: CircularProgressIndicator(
                key: const ValueKey('sign-in-seal-ring'),
                strokeWidth: 3,
                color: p.info.fill,
              ),
            ),
          AnimatedBuilder(
            animation: Listenable.merge([enter, pulse]),
            builder: (context, child) => Opacity(
              opacity: _enter.value.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: (0.7 + 0.3 * enter.value) * (1 + 0.06 * pulse.value),
                child: child,
              ),
            ),
            child: const SagipMark(size: _size),
          ),
        ],
      ),
    );
  }
}

/// After a sign-in is accepted (Joshua, 2026-11-10): everything but the
/// seal goes; the seal floats up to the middle of the screen, then flies
/// toward the viewer, growing and fading, while the page behind it fades
/// to show the board.
class SealFlight extends StatefulWidget {
  const SealFlight({
    super.key,
    required this.from,
    required this.background,
    required this.onDone,
  });

  /// Where the seal sat on the card, on screen.
  final Rect from;

  /// The page color that hides the card, then fades.
  final Color background;
  final VoidCallback onDone;

  static const duration = Duration(milliseconds: 1500);

  @override
  State<SealFlight> createState() => _SealFlightState();
}

class _SealFlightState extends State<SealFlight>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: SealFlight.duration,
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // 0 to 0.4: float to the middle, a little above it, and settle.
    final float = CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 0.4, curve: Curves.easeInOutCubic),
    );
    // 0.45 to 1: fly forward and fade.
    final fly = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.45, 1, curve: Curves.easeInCubic),
    );
    // The page behind fades from 0.55, showing the board.
    final reveal = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.55, 1, curve: Curves.easeOut),
    );
    final start = widget.from.center;
    final middle = Offset(screen.width / 2, screen.height / 2);
    // The box holds the seal and its ring: the seal is the inner part.
    final size =
        widget.from.width * _AnimatedSealState._size / _AnimatedSealState._ring;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // A gentle rise that peaks mid-float and settles.
          final lift = -24 * math.sin(math.pi * float.value);
          final at = Offset.lerp(start, middle, float.value)! + Offset(0, lift);
          final scale = 1 + 0.25 * float.value + 5 * fly.value;
          return Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: widget.background.withValues(alpha: 1 - reveal.value),
                ),
              ),
              Positioned(
                left: at.dx - size / 2,
                top: at.dy - size / 2,
                width: size,
                height: size,
                child: Opacity(
                  opacity: (1 - fly.value).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale,
                    child: SagipMark(size: size),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
