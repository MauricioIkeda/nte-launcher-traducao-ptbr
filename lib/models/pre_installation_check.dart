enum PreInstallationCheckStatus { passed, warning, failed }

class PreInstallationCheck {
  const PreInstallationCheck({
    required this.id,
    required this.label,
    required this.detail,
    required this.status,
  });

  final String id;
  final String label;
  final String detail;
  final PreInstallationCheckStatus status;
}

class PreInstallationReport {
  const PreInstallationReport(this.checks);

  final List<PreInstallationCheck> checks;

  bool get canProceed => checks.every(
    (check) => check.status != PreInstallationCheckStatus.failed,
  );

  int get passedCount => checks
      .where((check) => check.status == PreInstallationCheckStatus.passed)
      .length;

  int get warningCount => checks
      .where((check) => check.status == PreInstallationCheckStatus.warning)
      .length;

  List<PreInstallationCheck> get failures => checks
      .where((check) => check.status == PreInstallationCheckStatus.failed)
      .toList(growable: false);

  String get failureSummary => failures.map((check) => check.detail).join(' ');
}
