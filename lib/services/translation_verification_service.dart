import 'dart:io';

import '../core/launcher_log.dart';
import '../models/install_receipt.dart';
import '../models/loaded_translation_manifest.dart';
import '../models/translation_installation.dart';
import 'file_integrity_service.dart';
import 'game_language_service.dart';
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
    GameLanguageService? gameLanguage,
  }) : gameLanguage = gameLanguage ?? GameLanguageService();

  final FileIntegrityService integrity;
  final ReceiptRepository receipts;
  final SafePathService safePaths;
  final LauncherLog log;
  final GameLanguageService gameLanguage;

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

    final languageReceipt = receiptResult.receipt?.textLanguage;
    if (manifest.localization?.installationCulture == 'fr' &&
        languageReceipt?.requestedCulture == 'fr') {
      try {
        final prepared = await gameLanguage.ensureCulture(
          'fr',
          previous: languageReceipt,
          gameDirectory: gameDirectory,
        );
        if (prepared.changed) {
          await log.info(
            'Cultura preparada: launcher oficial em inglês e jogo no slot '
            'francês/PT-BR.',
          );
        }
      } catch (error, stackTrace) {
        await log.error(
          'Não foi possível preparar automaticamente a cultura do NTE.',
          error: error,
          stackTrace: stackTrace,
        );
      }
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

    var receipt = receiptResult.receipt;
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
      if (manifest.localization?.installationCulture == 'fr' &&
          receipt != null &&
          receipt.textLanguage == null) {
        receipt = await _migrateHostedLanguageReceipt(
          receipt,
          gameDirectory,
        );
      }
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

  Future<InstallReceipt> _migrateHostedLanguageReceipt(
    InstallReceipt receipt,
    String gameDirectory,
  ) async {
    try {
      final prepared = await gameLanguage.ensureCulture(
        'fr',
        gameDirectory: gameDirectory,
      );
      final textLanguage = prepared.receipt;
      if (textLanguage == null) {
        await log.info(
          'A instalação hospedada em fr foi detectada, mas a cultura não '
          'pôde ser preparada automaticamente: '
          '${prepared.reason ?? 'motivo desconhecido'}.',
        );
        return receipt;
      }
      final migrated = InstallReceipt(
        schemaVersion: receipt.schemaVersion,
        translationVersion: receipt.translationVersion,
        installedAt: receipt.installedAt,
        gameDirectory: receipt.gameDirectory,
        manifestSha256: receipt.manifestSha256,
        manifestPublishedAt: receipt.manifestPublishedAt,
        gameBuildId: receipt.gameBuildId,
        sourceHash: receipt.sourceHash,
        textLanguage: textLanguage,
        files: receipt.files,
      );
      await receipts.write(gameDirectory, migrated);
      await log.info(
        'Instalação existente migrada para cultura hospedada: launcher '
        'oficial em inglês e jogo no slot francês/PT-BR.',
      );
      return migrated;
    } catch (error, stackTrace) {
      await log.error(
        'Não foi possível migrar automaticamente a cultura da instalação '
        'existente.',
        error: error,
        stackTrace: stackTrace,
      );
      return receipt;
    }
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
