import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Standard page frame for table and card pages: title, optional subtitle
/// and header actions, then scrolling content with 24 px side padding.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.headerTrailing,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? headerTrailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(SagipSpace.xxl),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.headlineSmall),
                  if (subtitle != null) ...[
                    const SizedBox(height: SagipSpace.xs),
                    Text(subtitle!, style: text.bodySmall),
                  ],
                ],
              ),
            ),
            ?headerTrailing,
          ],
        ),
        const SizedBox(height: SagipSpace.xl),
        child,
      ],
    );
  }
}

/// A card that scrolls a wide [DataTable] sideways on narrow windows.
class TableCard extends StatelessWidget {
  const TableCard({super.key, required this.table});

  final DataTable table;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: table,
          ),
        ),
      ),
    );
  }
}
