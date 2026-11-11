import 'package:flutter/foundation.dart';
import 'package:rpg_api/rpg_api.dart' show
    LocalRpgWorldIntakeApi, RpgWorldIntakePreview,
    LocalRpgBookGameplayAuditApi, RpgBookGameplayAudit;

/// A message-only worker, never capture BuildContext or widget State.
RpgWorldIntakePreview _nativeReview((Uint8List, String?) input) =>
    const LocalRpgWorldIntakeApi().inspect(
        input.$1, readinessJson: input.$2);

Future<RpgWorldIntakePreview> reviewImportedWorldInWorker(
        Uint8List archive, String? readiness) =>
    compute(_nativeReview, (archive, readiness),
        debugLabel: 'native-rpg-world-intake');

RpgBookGameplayAudit _nativeGameAudit(Uint8List bytes) =>
    const LocalRpgBookGameplayAuditApi().inspect(bytes);

Future<RpgBookGameplayAudit> auditImportedWorldInWorker(
        Uint8List archive) =>
    compute(_nativeGameAudit, archive,
        debugLabel: 'native-rpg-campaign-causality');
