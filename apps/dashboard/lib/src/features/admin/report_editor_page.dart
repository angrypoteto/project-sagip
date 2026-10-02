import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

import '../../common/actions.dart';
import '../../common/download.dart';
import '../../common/labels.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../router.dart';
import '../common_page.dart';
import 'report_pdf.dart';
import 'reports_page.dart';

/// The name the unsaved-changes guard knows this page by.
const reportUnsavedId = 'report';

enum _Step { period, collecting, empty, failed, review }

enum _Preset { day, week, month, custom }

/// A6: make an NDRRMC report (Objective 4). Choose a period, collect the
/// records, then review the draft beside the figures it came from, edit
/// it, save it, mark it final, and download the PDF.
///
/// With [reportId] it opens a saved report: a draft for more editing, a
/// final report to read and download.
class ReportEditorPage extends ConsumerStatefulWidget {
  const ReportEditorPage({super.key, this.reportId});

  final String? reportId;

  @override
  ConsumerState<ReportEditorPage> createState() => _ReportEditorPageState();
}

class _ReportEditorPageState extends ConsumerState<ReportEditorPage> {
  final _title = TextEditingController();
  final _bodies = <String, TextEditingController>{};
  var _sections = const <ReportSection>[];

  late var _step = widget.reportId == null ? _Step.period : _Step.review;
  var _preset = _Preset.week;
  DateTimeRange? _custom;
  DateTime? _from;
  DateTime? _to;
  ReportSource? _source;
  int? _generationMs;

  /// The report as the server last gave it; null for a draft not saved yet.
  NdrrmcReport? _saved;

  /// The text as last saved, to tell whether anything was typed since.
  String? _savedText;
  var _busy = false;

  /// True while the fields are being filled, so that does not count as
  /// typing.
  var _filling = false;

  final _stopwatch = Stopwatch();
  Timer? _ticker;
  late final UnsavedChanges _unsaved = ref.read(unsavedChangesProvider);

  @override
  void initState() {
    super.initState();
    _title.addListener(_typed);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _unsaved.set(reportUnsavedId, dirty: false);
    _title.dispose();
    for (final c in _bodies.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<ReportSection> get _current => [
    for (final s in _sections) s.withBody(_bodies[s.key]!.text),
  ];

  /// Title and bodies as one string, for comparing.
  String _textOf(String title, List<ReportSection> sections) => [
    title.trim(),
    for (final s in sections) '${s.key}\n${s.body}',
  ].join('\u0000');

  bool get _isFinal => _saved?.isFinal ?? false;

  bool get _dirty =>
      _step == _Step.review &&
      !_isFinal &&
      _textOf(_title.text, _current) != _savedText;

  void _typed() {
    if (_filling) return;
    _unsaved.set(reportUnsavedId, dirty: _dirty);
    if (mounted) setState(() {});
  }

  /// Puts a report's text into the fields.
  void _fill(String title, List<ReportSection> sections) {
    _filling = true;
    for (final c in _bodies.values) {
      c.dispose();
    }
    _bodies
      ..clear()
      ..addAll({
        for (final s in sections)
          s.key: TextEditingController(text: s.body)..addListener(_typed),
      });
    _sections = sections;
    _title.text = title;
    _filling = false;
  }

  /// Takes in the saved report: the first time, and whenever the server's
  /// copy changes. Unsaved typing is kept unless the report became final.
  void _sync(NdrrmcReport report) {
    final before = _saved;
    if (before != null &&
        before.updatedAt == report.updatedAt &&
        before.status == report.status) {
      return;
    }
    final keepTyping = before != null && _dirty && !report.isFinal;
    _saved = report;
    _source = report.source;
    _from = report.periodStart;
    _to = report.periodEnd;
    _generationMs = report.generationMs;
    _step = _Step.review;
    if (!keepTyping) {
      final incoming = _textOf(report.title, report.sections);
      if (_sections.isEmpty || _textOf(_title.text, _current) != incoming) {
        _fill(report.title, report.sections);
      }
      _savedText = incoming;
    }
    _unsaved.set(reportUnsavedId, dirty: _dirty);
  }

  /// The chosen period: a rolling window ending now, or whole days.
  (DateTime, DateTime)? get _period {
    final now = ref.read(analyticsNowProvider)();
    return switch (_preset) {
      _Preset.day => (now.subtract(const Duration(days: 1)), now),
      _Preset.week => (now.subtract(const Duration(days: 7)), now),
      _Preset.month => (now.subtract(const Duration(days: 30)), now),
      _Preset.custom => switch (_custom) {
        null => null,
        final range => (
          DateTime(range.start.year, range.start.month, range.start.day),
          DateTime(range.end.year, range.end.month, range.end.day + 1),
        ),
      },
    };
  }

  Future<void> _pickDates() async {
    final now = ref.read(analyticsNowProvider)();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: _custom,
    );
    if (picked != null && mounted) setState(() => _custom = picked);
  }

  Future<void> _collect() async {
    final period = _period;
    if (period == null) return;
    final (from, to) = period;
    setState(() {
      _from = from;
      _to = to;
      _step = _Step.collecting;
    });
    _stopwatch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
    try {
      final source = await ref.read(reportRepositoryProvider).source(from, to);
      if (!mounted) return;
      if (source.isEmpty) {
        setState(() => _step = _Step.empty);
        return;
      }
      _fill(defaultReportTitle(from, to), draftReportSections(source));
      setState(() {
        _source = source;
        _generationMs = _stopwatch.elapsedMilliseconds;
        _step = _Step.review;
      });
      _unsaved.set(reportUnsavedId, dirty: true);
    } on ActionRejected {
      if (mounted) setState(() => _step = _Step.failed);
    } finally {
      _stopwatch.stop();
      _ticker?.cancel();
    }
  }

  /// Saves the text. Returns the report's id, or null when it was refused.
  Future<String?> _save({bool quiet = false}) async {
    final l10n = AppLocalizations.of(context);
    final router = GoRouter.of(context);
    final sending = _textOf(_title.text, _current);
    final wasNew = _saved == null;
    String? id;
    setState(() => _busy = true);
    await runAction(context, () async {
      id = await ref
          .read(reportRepositoryProvider)
          .save(
            id: _saved?.id,
            from: _from!,
            to: _to!,
            title: _title.text,
            sections: _current,
            generationMs: _generationMs,
          );
    }, success: quiet ? null : l10n.reportSaved);
    if (id == null) {
      if (mounted) setState(() => _busy = false);
      return null;
    }
    _savedText = sending;
    _unsaved.set(reportUnsavedId, dirty: false);
    if (mounted) setState(() => _busy = false);
    // A new draft now has an address of its own.
    if (wasNew) router.go(Routes.report(id!));
    return id;
  }

  Future<void> _finalize() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(reportRepositoryProvider);
    final failing = ReportCheck.values
        .where((c) => !passedReportChecks(_source!, _current).contains(c))
        .toList();
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.reportFinalizeTitle),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.reportFinalizeBody),
              if (failing.isNotEmpty) ...[
                const SizedBox(height: SagipSpace.md),
                Text(l10n.reportFinalizeUnmet(failing.length)),
                for (final c in failing)
                  Padding(
                    padding: const EdgeInsets.only(top: SagipSpace.xs),
                    child: Text(l10n.reportCheckFailed(l10n.reportCheck(c))),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey('report-finalize-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.reportFinalize),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    // What is on screen is what becomes final.
    final id = _dirty ? await _save(quiet: true) : _saved?.id;
    if (id == null) return;
    if (mounted) setState(() => _busy = true);
    try {
      await repository.finalize(id);
      messenger.showSnackBar(statusSnack(l10n.reportFinalized));
    } on ActionRejected catch (e) {
      messenger.showSnackBar(statusSnack(l10n.actionRejection(e.reason)));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _download() async {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final saved = _saved;
    final bytes = await buildReportPdf(
      title: _title.text.trim(),
      sections: _current,
      labels: ReportPdfLabels(
        agency: l10n.reportPdfAgency,
        period: l10n.reportPdfPeriod(
          formatDateTime(_from!, locale),
          formatDateTime(_to!, locale),
        ),
        status: saved != null && saved.isFinal
            ? l10n.reportPdfFinal(
                saved.finalizedByName ?? saved.createdByName,
                formatDateTime(saved.finalizedAt ?? saved.updatedAt, locale),
              )
            : l10n.reportPdfDraft,
        prepared: saved == null
            ? null
            : l10n.reportPdfPrepared(
                saved.createdByName,
                formatDateTime(saved.createdAt, locale),
              ),
        footer: l10n.reportPdfFooter,
        emptySection: l10n.reportPdfEmptySection,
      ),
    );
    downloadBytes('${saved?.id ?? 'ndrrmc-report-draft'}.pdf', bytes);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final id = widget.reportId;

    if (id != null) {
      final reports = ref.watch(reportsProvider);
      final report = reports.value?.where((r) => r.id == id).firstOrNull;
      if (report != null) {
        _sync(report);
      } else if (_saved?.id != id && _savedText == null) {
        return PageFrame(
          title: l10n.reportsTitle,
          child: reports.hasValue
              ? EmptyState(
                  icon: Symbols.description_rounded,
                  title: l10n.reportNotFound,
                  action: TextButton(
                    onPressed: () => context.go(Routes.reports),
                    child: Text(l10n.reportBackToList),
                  ),
                )
              : reports.hasError
              ? ErrorState(
                  message: l10n.loadFailed,
                  retryLabel: l10n.retry,
                  onRetry: () => ref.invalidate(reportsProvider),
                )
              : const SkeletonList(),
        );
      }
    }

    return switch (_step) {
      _Step.period => _periodStep(l10n),
      _Step.collecting => _collectingStep(l10n),
      _Step.empty => PageFrame(
        title: l10n.reportNewTitle,
        child: EmptyState(
          icon: Symbols.event_busy_rounded,
          title: l10n.reportNoIncidents,
          action: TextButton(
            onPressed: () => setState(() => _step = _Step.period),
            child: Text(l10n.reportChoosePeriod),
          ),
        ),
      ),
      _Step.failed => PageFrame(
        title: l10n.reportNewTitle,
        child: ErrorState(
          message: l10n.reportCollectFailed,
          retryLabel: l10n.retry,
          onRetry: _collect,
        ),
      ),
      _Step.review => _reviewStep(l10n),
    };
  }

  Widget _periodStep(AppLocalizations l10n) {
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final online = ref.watch(isOnlineProvider);
    final custom = _custom;
    return PageFrame(
      title: l10n.reportNewTitle,
      subtitle: l10n.reportNewSubtitle,
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(SagipSpace.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.reportPeriodTitle, style: text.titleMedium),
                  const SizedBox(height: SagipSpace.xs),
                  Text(l10n.reportPeriodNote, style: text.bodySmall),
                  const SizedBox(height: SagipSpace.lg),
                  SegmentedButton<_Preset>(
                    segments: [
                      ButtonSegment(
                        value: _Preset.day,
                        label: Text(l10n.periodDay),
                      ),
                      ButtonSegment(
                        value: _Preset.week,
                        label: Text(l10n.periodWeek),
                      ),
                      ButtonSegment(
                        value: _Preset.month,
                        label: Text(l10n.periodMonth),
                      ),
                      ButtonSegment(
                        value: _Preset.custom,
                        label: Text(l10n.reportPeriodCustom),
                      ),
                    ],
                    selected: {_preset},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) {
                      setState(() => _preset = s.first);
                      if (s.first == _Preset.custom && _custom == null) {
                        _pickDates();
                      }
                    },
                  ),
                  if (_preset == _Preset.custom) ...[
                    const SizedBox(height: SagipSpace.md),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            custom == null
                                ? l10n.reportPeriodNoDates
                                : l10n.reportPeriodDates(
                                    formatDate(custom.start, locale),
                                    formatDate(custom.end, locale),
                                  ),
                            style: text.bodyMedium,
                          ),
                        ),
                        TextButton(
                          onPressed: _pickDates,
                          child: Text(l10n.reportPeriodChange),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: SagipSpace.xl),
                  FilledButton(
                    key: const ValueKey('report-collect'),
                    onPressed: online && _period != null ? _collect : null,
                    child: Text(l10n.reportCollect),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _collectingStep(AppLocalizations l10n) {
    final text = Theme.of(context).textTheme;
    final seconds = (_stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1);
    return PageFrame(
      title: l10n.reportNewTitle,
      child: Padding(
        padding: const EdgeInsets.only(top: SagipSpace.x4),
        child: Column(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: SagipSpace.lg),
            Text(l10n.reportCollecting, style: text.titleMedium),
            const SizedBox(height: SagipSpace.xs),
            Text(
              l10n.reportElapsed(seconds),
              style: text.bodySmall!.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewStep(AppLocalizations l10n) {
    final p = SagipPalette.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).toString();
    final online = ref.watch(isOnlineProvider);
    final saved = _saved;
    final isFinal = _isFinal;
    final source = _source!;
    final passed = passedReportChecks(source, _current);
    final accepted = reportTextAccepted(_title.text, _current);

    return PageFrame(
      title: saved == null ? l10n.reportNewTitle : saved.id,
      subtitle: l10n.reportPeriod(
        formatDateTime(_from!, locale),
        formatDateTime(_to!, locale),
      ),
      headerTrailing: Wrap(
        spacing: SagipSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SagipChip.status(
            label: isFinal ? l10n.reportStatusFinal : l10n.reportStatusDraft,
            visual: reportStatusVisual(
              isFinal ? ReportStatus.finalized : ReportStatus.draft,
              p,
            ),
          ),
          TextButton.icon(
            key: const ValueKey('report-download'),
            onPressed: accepted ? _download : null,
            icon: const Icon(Symbols.download_rounded),
            label: Text(l10n.reportDownload),
          ),
          if (!isFinal) ...[
            OutlinedButton(
              key: const ValueKey('report-finalize'),
              onPressed: online && !_busy && accepted ? _finalize : null,
              child: Text(l10n.reportFinalize),
            ),
            FilledButton(
              key: const ValueKey('report-save'),
              onPressed: online && !_busy && accepted && _dirty ? _save : null,
              child: Text(_busy ? l10n.working : l10n.reportSave),
            ),
          ],
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(SagipSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const ValueKey('report-title'),
                      controller: _title,
                      readOnly: isFinal,
                      maxLength: ReportSections.maxTitle,
                      style: text.titleMedium,
                      decoration: InputDecoration(
                        labelText: l10n.reportTitleLabel,
                        errorText: _title.text.trim().isEmpty
                            ? l10n.reportTitleError
                            : null,
                      ),
                    ),
                    for (final (i, s) in _sections.indexed) ...[
                      const SizedBox(height: SagipSpace.lg),
                      Text('${i + 1}. ${s.title}', style: text.titleSmall),
                      const SizedBox(height: SagipSpace.sm),
                      TextField(
                        key: ValueKey('report-section-${s.key}'),
                        controller: _bodies[s.key],
                        readOnly: isFinal,
                        minLines: 2,
                        maxLines: null,
                        maxLength: ReportSections.maxBody,
                        decoration: InputDecoration(
                          hintText: s.key == ReportSections.remarks
                              ? l10n.reportRemarksHint
                              : null,
                          counterText: '',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: SagipSpace.lg),
          SizedBox(
            width: 340,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FiguresCard(source: source),
                const SizedBox(height: SagipSpace.lg),
                _ChecklistCard(passed: passed),
                const SizedBox(height: SagipSpace.lg),
                Text(
                  _generationMs == null
                      ? l10n.reportMethodNote
                      : '${l10n.reportDraftedIn((_generationMs! / 1000).toStringAsFixed(1))} '
                            '${l10n.reportMethodNote}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The figures the draft was written from, so each sentence can be
/// checked against its number.
class _FiguresCard extends StatelessWidget {
  const _FiguresCard({required this.source});

  final ReportSource source;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    final rows = [
      (l10n.figIncidents, source.incidents),
      (l10n.figSos, source.sos),
      (l10n.figClusters, source.clusters),
      (l10n.figResolved, source.resolved),
      (l10n.figOpen, source.open),
      (l10n.figFalse, source.falseReports),
      (l10n.figVulnerable, source.vulnerableIncidents),
      (l10n.figCompletions, source.completionReports),
      (l10n.figAssisted, source.personsAssisted),
      (l10n.figInjured, source.injured),
      (l10n.figMissing, source.missing),
      (l10n.figFamilies, source.affectedFamilies),
      (l10n.figHouses, source.housesDamaged),
      (l10n.figDispatches, source.dispatches),
      (l10n.figUnits, source.unitsDeployed),
      (l10n.figAlerts, source.alertsIssued),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.reportFigures, style: text.titleSmall),
            const SizedBox(height: SagipSpace.xs),
            Text(l10n.reportFiguresNote, style: text.bodySmall),
            const SizedBox(height: SagipSpace.sm),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: text.bodyMedium!.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      '$value',
                      style: text.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What to look at before calling the report final.
class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({required this.passed});

  final Set<ReportCheck> passed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final p = SagipPalette.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SagipSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.reportChecklist, style: text.titleSmall),
            const SizedBox(height: SagipSpace.sm),
            for (final c in ReportCheck.values)
              Padding(
                key: ValueKey(
                  'check-${c.name}-${passed.contains(c) ? 'ok' : 'open'}',
                ),
                padding: const EdgeInsets.symmetric(vertical: SagipSpace.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      passed.contains(c)
                          ? Symbols.check_circle_rounded
                          : Symbols.error_rounded,
                      size: 20,
                      color: passed.contains(c)
                          ? p.success.text
                          : p.warning.text,
                    ),
                    const SizedBox(width: SagipSpace.sm),
                    Expanded(
                      child: Text(
                        passed.contains(c)
                            ? l10n.reportCheck(c)
                            : l10n.reportCheckFailed(l10n.reportCheck(c)),
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
