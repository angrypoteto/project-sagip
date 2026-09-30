import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/sagip_palette.dart';
import '../theme/sagip_tokens.dart';

/// Empty state: one quiet icon plus text that invites the next step.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(SagipSpace.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 36, color: p.textSecondary),
              const SizedBox(height: SagipSpace.md),
              Text(title, style: text.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: SagipSpace.sm),
                Text(
                  message!,
                  style: text.bodyMedium!.copyWith(color: p.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: SagipSpace.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Error state: says what happened and offers a retry.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel,
  });

  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Symbols.error_rounded,
      title: message,
      action: onRetry == null
          ? null
          : OutlinedButton(onPressed: onRetry, child: Text(retryLabel ?? '')),
    );
  }
}

/// A rounded placeholder block for skeleton loading states.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius});

  final double? width;
  final double height;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: SagipPalette.of(context).hairline,
        borderRadius: BorderRadius.circular(radius ?? SagipRadius.chip),
      ),
    );
  }
}

/// Skeleton rows shaped like list rows while data loads.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 6, this.rowHeight = 64});

  final int rows;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SagipSpace.lg,
              vertical: SagipSpace.sm,
            ),
            child: Row(
              children: [
                const SkeletonBox(width: 20, height: 20),
                const SizedBox(width: SagipSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 120 + (i % 3) * 40.0, height: 12),
                      const SizedBox(height: SagipSpace.sm),
                      const SkeletonBox(width: 180, height: 10),
                      SizedBox(height: rowHeight - 46),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
