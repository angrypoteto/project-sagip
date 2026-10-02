import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sagip_shared/sagip_shared.dart';

/// The fixed words on the PDF, from the app's l10n file.
class ReportPdfLabels {
  const ReportPdfLabels({
    required this.agency,
    required this.period,
    required this.status,
    required this.prepared,
    required this.footer,
    required this.emptySection,
  });

  /// The department's name above the title.
  final String agency;

  /// "Period covered: ..." with the dates filled in.
  final String period;

  /// "Draft, not yet final" or "Final, ...".
  final String status;

  /// "Prepared by ... on ...", or null for a draft not saved yet.
  final String? prepared;

  /// One line at the bottom of every page.
  final String footer;

  /// What a section with no text says.
  final String emptySection;
}

/// Fonts for the PDF: the app's own typeface, so every character the
/// dashboard shows also prints. Loaded once.
Future<({pw.Font regular, pw.Font bold})> _fonts() async {
  const dir = 'packages/sagip_shared/assets/fonts';
  final regular = await rootBundle.load('$dir/PlusJakartaSans-Regular.ttf');
  final bold = await rootBundle.load('$dir/PlusJakartaSans-Bold.ttf');
  return (regular: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));
}

/// A6 step 4: the report as an A4 PDF. Text only: title, period, status,
/// then each section under its heading.
Future<Uint8List> buildReportPdf({
  required String title,
  required List<ReportSection> sections,
  required ReportPdfLabels labels,
}) async {
  final fonts = await _fonts();
  final theme = pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold);
  final small = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);
  final doc = pw.Document(title: title, author: labels.agency);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(56, 56, 56, 48),
      theme: theme,
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(labels.footer, style: small),
          pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: small,
          ),
        ],
      ),
      build: (context) => [
        pw.Text(labels.agency, style: small),
        pw.SizedBox(height: 6),
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Text(labels.period, style: const pw.TextStyle(fontSize: 10)),
        pw.Text(labels.status, style: const pw.TextStyle(fontSize: 10)),
        if (labels.prepared != null)
          pw.Text(labels.prepared!, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 0.5, color: PdfColors.grey500),
        for (final (i, s) in sections.indexed) ...[
          pw.SizedBox(height: 14),
          pw.Text(
            '${i + 1}. ${s.title}',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Paragraph(
            text: s.body.trim().isEmpty ? labels.emptySection : s.body.trim(),
            style: pw.TextStyle(
              fontSize: 10.5,
              lineSpacing: 3,
              color: s.body.trim().isEmpty ? PdfColors.grey600 : null,
            ),
          ),
        ],
      ],
    ),
  );
  return doc.save();
}
