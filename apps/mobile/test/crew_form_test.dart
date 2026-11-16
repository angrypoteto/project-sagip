import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_mobile/src/features/responder/complete_page.dart';
import 'package:sagip_mobile/src/l10n/app_localizations_en.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  final l10n = AppLocalizationsEn();

  CompletionDraft draft(CompletionDetails x, {RescueOutcome? outcome}) =>
      CompletionDraft(
        incidentId: 'INC-0001',
        outcome: outcome ?? RescueOutcome.transported,
        details: x,
      );

  test('a missing hospital names the patient (2026-11-17)', () {
    final d = draft(
      const CompletionDetails(
        emrType: EmrType.medicalCall,
        patients: [
          PatientRecord(hospital: 'UERM'),
          PatientRecord(),
        ],
      ),
    );
    expect(
      missingAnswer(l10n, 'medical', d),
      'Answer "Receiving hospital" for Patient 2 before you submit.',
    );
  });

  test('the form questions in order; none for a false report', () {
    expect(
      missingAnswer(l10n, 'medical', draft(const CompletionDetails())),
      'Answer "Type of EMR" before you submit.',
    );
    expect(
      missingAnswer(
        l10n,
        'medical',
        draft(const CompletionDetails(emrType: EmrType.roadAccident)),
      ),
      'Answer "Cause of road accident" before you submit.',
    );
    expect(
      missingAnswer(
        l10n,
        'flood',
        draft(const CompletionDetails(floodCause: FloodCause.stormSurge)),
      ),
      'Answer "Flood level" before you submit.',
    );
    expect(
      missingAnswer(l10n, 'fire', draft(const CompletionDetails())),
      isNull,
    );
    expect(
      missingAnswer(
        l10n,
        'medical',
        draft(const CompletionDetails(), outcome: RescueOutcome.falseReport),
      ),
      isNull,
    );
  });
}
