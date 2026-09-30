import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../l10n/app_localizations.dart';

/// Renders the loading, empty, error, and data states of an [AsyncValue]
/// the same way on every screen (CLAUDE.md: every screen handles four
/// states; the offline state is the shell's banner plus disabled actions).
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.value,
    required this.builder,
    this.isEmpty,
    this.empty,
    this.loading,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final bool Function(T data)? isEmpty;
  final Widget? empty;
  final Widget? loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Keep showing the last good data while a refresh or error happens.
    if (value.hasValue) {
      final data = value.requireValue;
      if (isEmpty != null && isEmpty!(data) && empty != null) return empty!;
      return builder(data);
    }
    if (value.hasError) {
      return ErrorState(
        message: l10n.loadFailed,
        onRetry: onRetry,
        retryLabel: l10n.retry,
      );
    }
    return loading ?? const SkeletonList();
  }
}
