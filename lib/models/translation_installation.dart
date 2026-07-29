enum TranslationInstallationStatus {
  checking,
  notInstalled,
  installedCurrent,
  installedOutdated,
  incomplete,
  modified,
  managedInAnotherDirectory,
  incompatibleGameBuild,
  unverifiable,
}

class TranslationVerificationResult {
  const TranslationVerificationResult({
    required this.status,
    this.validFiles = const [],
    this.missingFiles = const [],
    this.modifiedFiles = const [],
    this.unverifiableFiles = const [],
    this.detectedVersion,
    this.receiptVersion,
    this.error,
    this.managedDirectory,
  });

  const TranslationVerificationResult.checking()
    : this(status: TranslationInstallationStatus.checking);

  final TranslationInstallationStatus status;
  final List<String> validFiles;
  final List<String> missingFiles;
  final List<String> modifiedFiles;
  final List<String> unverifiableFiles;
  final String? detectedVersion;
  final String? receiptVersion;
  final Object? error;
  final String? managedDirectory;

  bool get hasInstalledFiles => switch (status) {
    TranslationInstallationStatus.checking ||
    TranslationInstallationStatus.notInstalled ||
    TranslationInstallationStatus.managedInAnotherDirectory => false,
    _ =>
      validFiles.isNotEmpty ||
          modifiedFiles.isNotEmpty ||
          unverifiableFiles.isNotEmpty ||
          receiptVersion != null,
  };

  bool get isVerified =>
      status == TranslationInstallationStatus.installedCurrent ||
      status == TranslationInstallationStatus.installedOutdated;

  bool get needsRepair =>
      status == TranslationInstallationStatus.incomplete ||
      status == TranslationInstallationStatus.modified;
}
