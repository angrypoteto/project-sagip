import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../l10n/app_localizations.dart';

/// The Command Center is for a computer (Joshua, 2026-11-10: "if someone
/// opened the system on a phone ... suggest to use a pc"). On a phone-sized
/// screen it first asks to use a PC, and points crews and residents to the
/// app. "Continue anyway" shows the dashboard for this visit.
class PhoneNotice extends StatefulWidget {
  const PhoneNotice({super.key, required this.child});

  final Widget child;

  /// Narrower than this on its short side: a phone.
  static const phoneWidth = 600.0;

  @override
  State<PhoneNotice> createState() => _PhoneNoticeState();
}

class _PhoneNoticeState extends State<PhoneNotice> {
  var _continued = false;

  @override
  Widget build(BuildContext context) {
    final phone =
        MediaQuery.sizeOf(context).shortestSide < PhoneNotice.phoneWidth;
    if (!phone || _continued) return widget.child;
    return _Notice(onContinue: () => setState(() => _continued = true));
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return Material(
      key: const ValueKey('phone-notice'),
      color: p.canvas,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SagipSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: SagipMark(size: 64)),
                  const SizedBox(height: SagipSpace.xl),
                  Icon(Symbols.computer_rounded, size: 40, color: p.info.text),
                  const SizedBox(height: SagipSpace.md),
                  Text(
                    l10n.phoneNoticeTitle,
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: SagipSpace.sm),
                  Text(
                    l10n.phoneNoticeBody,
                    style: text.bodyMedium!.copyWith(color: p.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: SagipSpace.lg),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: p.info.tint,
                      borderRadius: BorderRadius.circular(SagipRadius.card),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(SagipSpace.lg),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Symbols.smartphone_rounded, color: p.info.text),
                          const SizedBox(width: SagipSpace.md),
                          Expanded(
                            child: Text(
                              l10n.phoneNoticeApp,
                              style: text.bodyMedium!.copyWith(
                                color: p.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: SagipSpace.xl),
                  TextButton(
                    key: const ValueKey('phone-notice-continue'),
                    onPressed: onContinue,
                    child: Text(l10n.phoneNoticeContinue),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
