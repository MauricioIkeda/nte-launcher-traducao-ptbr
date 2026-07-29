import 'dart:io';

import '../core/launcher_log.dart';
import '../models/install_receipt.dart';
import '../models/loaded_translation_manifest.dart';
import '../models/translation_installation.dart';
import 'file_integrity_service.dart';
import 'receipt_repository.dart';
import 'safe_path_service.dart';

typedef VerificationProgress =
    void Function(String currentFile, int verified, int total);

class TranslationVerificationService {
  TranslationVerificationService({
    required this.integrity,
    required this.receipts,
    required this.safePaths,
    required this.log,
  });

  final FileIntegrityService integrity;
  final ReceiptRepository receipts;
  final SafePathService safePaths;
  final LauncherLog log;

  Future<TranslationVerificationResult> verify({
    required LoadedTranslationManifest loadedManifest,
    required String gameDirectory,
    VerificationProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    final manifest = loadedManifest.manifest;
    if (!await Directory(gameDirectory).exists()) {
      return const TranslationVerificationResult(
        status: TranslationInstallationStatus.unverifiable,
        error: FileSystemException('O diretório do jogo não existe.'),
      );
    }
    final operation = integrity.startOperation(isCancelled: isCancelled);
    final valid = <String>[];
    final missing = <String>[];
    final modified = <String>[];
    final unverifiable = <String>[];
    final receiptResult = await receipts.read(gameDirectory);

    await log.info(
      'Iniciando verificação em '
      '${await safePaths.canonicalDirectory(gameDirectory)} '
      'com manifesto ${loadedManifest.source.name}.',
    );
    if (receiptResult.isInvalid || receiptResult.temporaryReceiptFound) {
      return TranslationVerificationResult(
        status: TranslationInstallationStatus.unverifiable,
        error:
            receiptResult.error ??
            const ReceiptFormatException(
              'Existe um recibo temporário abandonado.',
            ),
      );
    }

    try {
      var index = 0;
      for (final asset in manifest.files) {
        if (isCancelled?.call() == true) {
          return const TranslationVerificationResult(
            status: TranslationInstallationStatus.unverifiable,
            error: IntegrityCancelledException(),
          );
        }
        final destination = await safePaths.resolveFile(
          gameDirectory,
          asset.relativeDestination,
        );
        final result = await operation.verify(
          file: destination,
          expectedSize: asset.size,
          expectedSha256: asset.sha256,
        );
        index++;
        onProgress?.call(asset.name, index, manifest.files.length);
        switch (result.status) {
          case FileIntegrityStatus.valid:
            valid.add(asset.relativeDestination);
          case FileIntegrityStatus.missing:
            missing.add(asset.relativeDestination);
          case FileIntegrityStatus.sizeMismatch:
          case FileIntegrityStatus.hashMismatch:
            modified.add(asset.relativeDestination);
          case FileIntegrityStatus.accessDenied:
          case FileIntegrityStatus.inUse:
          case FileIntegrityStatus.readError:
          case FileIntegrityStatus.cancelled:
            unverifiable.add(asset.relativeDestination);
        }
        await log.info('Verificação ${asset.name}: ${result.status.name}.');
      }
    } catch (error, stackTrace) {
      await log.error(
        'Falha ao verificar caminhos da tradução.',
        error: error,
        stackTrace: stackTrace,
      );
      return TranslationVerificationResult(
        status: TranslationInstallationStatus.unverifiable,
        validFiles: valid,
        missingFiles: missing,
        modifiedFiles: modified,
        unverifiableFiles: unverifiable,
        receiptVersion: receiptResult.receipt?.translationVersion,
        error: error,
      );
    }

    final receipt = receiptResult.receipt;
    if (unverifiable.isNotEmpty) {
      return _result(
        TranslationInstallationStatus.unverifiable,
        receipt,
        valid,
        missing,
        modified,
        unverifiable,
      );
    }
    if (valid.length == manifest.files.length) {
      return _result(
        TranslationInstallationStatus.installedCurrent,
        receipt,
        valid,
        missing,
        modified,
        unverifiable,
        detectedVersion: manifest.translationVersion,
      );
    }

    if (receipt == null &&
        valid.isEmpty &&
        modified.every(
          (relative) => relative
              .replaceAll('\\', '/')
              .toLowerCase()
              .endsWith('/version.dll'),
        )) {
      final others = await receipts.readOtherReceipts(gameDirectory);
      if (others.isNotEmpty) {
        return TranslationVerificationResult(
          status: TranslationInstallationStatus.managedInAnotherDirectory,
          missingFiles: missing,
          modifiedFiles: modified,
          managedDirectory: others.first.gameDirectory,
        );
      }
      return TranslationVerificationResult(
        status: TranslationInstallationStatus.notInstalled,
        missingFiles: missing,
        modifiedFiles: modified,
      );
    }

    if (receipt != null) {
      final previousState = await _verifyReceiptFiles(
        receipt,
        gameDirectory,
        operation,
      );
      if (previousState.allValid) {
        if (receipt.translationVersion == manifest.translationVersion) {
          return _result(
            TranslationInstallationStatus.modified,
            receipt,
            valid,
            missing,
            modified,
            unverifiable,
            detectedVersion: receipt.translationVersion,
          );
        }
        final remoteIsNewer =
            loadedManifest.isAuthoritative &&
            manifest.publishedAt.isAfter(receipt.manifestPublishedAt);
        if (remoteIsNewer &&
            manifest.translationVersion != receipt.translationVersion) {
          return _result(
            TranslationInstallationStatus.installedOutdated,
            receipt,
            valid,
            missing,
            modified,
            unverifiable,
            detectedVersion: receipt.translationVersion,
          );
        }
        return _result(
          TranslationInstallationStatus.installedCurrent,
          receipt,
          valid,
          missing,
          modified,
          unverifiable,
          detectedVersion: receipt.translationVersion,
        );
      }
    }

    if (missing.length == manifest.files.length && modified.isEmpty) {
      if (receipt != null) {
        return _result(
          TranslationInstallationStatus.incomplete,
          receipt,
          valid,
          missing,
          modified,
          unverifiable,
        );
      }
      final others = await receipts.readOtherReceipts(gameDirectory);
      if (others.isNotEmpty) {
        return TranslationVerificationResult(
          status: TranslationInstallationStatus.managedInAnotherDirectory,
          missingFiles: missing,
          managedDirectory: others.first.gameDirectory,
        );
      }
      return TranslationVerificationResult(
        status: TranslationInstallationStatus.notInstalled,
        missingFiles: missing,
      );
    }
    if (missing.isNotEmpty) {
      return _result(
        TranslationInstallationStatus.incomplete,
        receipt,
        valid,
        missing,
        modified,
        unverifiable,
      );
    }
    return _result(
      TranslationInstallationStatus.modified,
      receipt,
      valid,
      missing,
      modified,
      unverifiable,
    );
  }

  Future<({bool allValid})> _verifyReceiptFiles(
    InstallReceipt receipt,
    String gameDirectory,
    FileIntegrityOperation operation,
  ) async {
    for (final entry in receipt.files) {
      final destination = await safePaths.resolveFile(
        gameDirectory,
        entry.relativePath,
      );
      final result = await operation.verify(
        file: destination,
        expectedSize: entry.installedSize,
        expectedSha256: entry.installedSha256,
      );
      if (!result.isValid) {
        return (allValid: false);
      }
    }
    return (allValid: true);
  }

  TranslationVerificationResult _result(
    TranslationInstallationStatus status,
    InstallReceipt? receipt,
    List<String> valid,
    List<String> missing,
    List<String> modified,
    List<String> unverifiable, {
    String? detectedVersion,
  }) {
    return TranslationVerificationResult(
      status: status,
      validFiles: List.unmodifiable(valid),
      missingFiles: List.unmodifiable(missing),
      modifiedFiles: List.unmodifiable(modified),
      unverifiableFiles: List.unmodifiable(unverifiable),
      detectedVersion: detectedVersion,
      receiptVersion: receipt?.translationVersion,
    );
  }
}
