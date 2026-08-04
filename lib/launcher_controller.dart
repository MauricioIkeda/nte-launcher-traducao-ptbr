import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'core/app_paths.dart';
import 'core/launcher_log.dart';
import 'models/app_update_manifest.dart';
import 'models/loaded_translation_manifest.dart';
import 'models/pre_installation_check.dart';
import 'models/translation_installation.dart';
import 'models/translation_manifest.dart';
import 'services/app_update_service.dart';
import 'services/download_service.dart';
import 'services/elevation_service.dart';
import 'services/game_platform_service.dart';
import 'services/installation_service.dart';
import 'services/legacy_migration_service.dart';
import 'services/manifest_repository.dart';
import 'services/pre_installation_service.dart';
import 'services/settings_service.dart';
import 'services/translation_verification_service.dart';

enum LauncherStatus {
  starting,
  loadingManifest,
  verifying,
  preparing,
  ready,
  downloading,
  installing,
  updating,
  repairing,
  completed,
  removing,
  error,
}

class LauncherController extends ChangeNotifier {
  LauncherController({
    required this.paths,
    required this.log,
    required this.appUpdates,
    required this.manifests,
    required this.downloads,
    required this.elevation,
    required this.gamePlatforms,
    required this.installer,
    required this.settings,
    required this.verifier,
    required this.migration,
    PreInstallationService? preInstallation,
    this.autoInstall = false,
  }) : preInstallation =
           preInstallation ??
           PreInstallationService(installer: installer, elevation: elevation);

  final AppPaths paths;
  final LauncherLog log;
  final AppUpdateService appUpdates;
  final ManifestRepository manifests;
  final DownloadService downloads;
  final ElevationService elevation;
  final GamePlatformService gamePlatforms;
  final InstallationService installer;
  final LauncherSettings settings;
  final TranslationVerificationService verifier;
  final LegacyMigrationService migration;
  final PreInstallationService preInstallation;
  final bool autoInstall;

  LauncherStatus status = LauncherStatus.starting;
  LoadedTranslationManifest? loadedManifest;
  String? gameDirectory;
  GamePlatformInfo? gamePlatform;
  String? persistedInstalledVersion;
  TranslationVerificationResult verification =
      const TranslationVerificationResult.checking();
  String appVersion = '...';
  AppUpdateManifest? availableAppUpdate;
  bool checkingAppUpdate = false;
  bool updatingLauncher = false;
  bool automaticLauncherUpdates = false;
  int appUpdateReceivedBytes = 0;
  int appUpdateTotalBytes = 0;
  String? errorMessage;
  String? rejectedGameDirectory;
  String? gameDirectorySelectionError;
  bool validatingGameDirectory = false;
  PreInstallationReport? preInstallationReport;
  String currentFile = '';
  int receivedBytes = 0;
  int totalBytes = 0;
  int verifiedFiles = 0;
  int verificationTotalFiles = 0;
  bool _cancelRequested = false;
  int _operationGeneration = 0;
  bool _disposed = false;

  TranslationManifest? get manifest => loadedManifest?.manifest;
  ManifestSource? get manifestSource => loadedManifest?.source;
  bool get offlineMode => loadedManifest?.isOffline ?? false;
  String? get installedVersion =>
      verification.detectedVersion ?? verification.receiptVersion;
  double get progress {
    if (status == LauncherStatus.verifying) {
      return verificationTotalFiles <= 0
          ? 0
          : (verifiedFiles / verificationTotalFiles).clamp(0, 1);
    }
    return totalBytes <= 0 ? 0 : (receivedBytes / totalBytes).clamp(0, 1);
  }

  bool get isBusy =>
      validatingGameDirectory ||
      updatingLauncher ||
      status == LauncherStatus.starting ||
      status == LauncherStatus.loadingManifest ||
      status == LauncherStatus.verifying ||
      status == LauncherStatus.preparing ||
      status == LauncherStatus.downloading ||
      status == LauncherStatus.installing ||
      status == LauncherStatus.updating ||
      status == LauncherStatus.repairing ||
      status == LauncherStatus.removing;
  bool get canChangeGameDirectory =>
      !validatingGameDirectory &&
      !updatingLauncher &&
      status != LauncherStatus.starting &&
      status != LauncherStatus.loadingManifest &&
      status != LauncherStatus.preparing &&
      status != LauncherStatus.downloading &&
      status != LauncherStatus.installing &&
      status != LauncherStatus.updating &&
      status != LauncherStatus.repairing &&
      status != LauncherStatus.removing;
  bool get isInstalled => verification.hasInstalledFiles;
  bool get translationIsCurrent =>
      verification.status == TranslationInstallationStatus.installedCurrent;
  bool get translationUpdateAvailable =>
      verification.status == TranslationInstallationStatus.installedOutdated;
  bool get translationNeedsRepair =>
      verification.needsRepair && verification.receiptVersion != null;
  bool get hasUnmanagedChanges =>
      verification.needsRepair && verification.receiptVersion == null;
  bool get canInstall =>
      !isBusy &&
      manifest != null &&
      gameDirectory != null &&
      !hasUnmanagedChanges &&
      verification.status != TranslationInstallationStatus.unverifiable;
  bool get canRemove =>
      !isBusy && gameDirectory != null && verification.receiptVersion != null;

  Future<void> initialize() async {
    final operation = ++_operationGeneration;
    status = LauncherStatus.starting;
    verification = const TranslationVerificationResult.checking();
    _notify();
    try {
      final savedGameDirectory = await settings.getGameDirectory();
      persistedInstalledVersion = await settings.getInstalledVersion();
      automaticLauncherUpdates = await settings.getAutomaticLauncherUpdates();
      // Force every existing installation away from the unsafe cold
      // /autoplay path, including users who previously enabled the option.
      await settings.setOfficialAutoplay(false);
      final savedResolution = savedGameDirectory == null
          ? null
          : await installer.resolveGameDirectory(savedGameDirectory);
      if (savedResolution != null) {
        gameDirectory = savedResolution.gameDirectory;
        if (savedResolution.wasAdjusted) {
          await settings.setGameDirectory(gameDirectory!);
          await log.info(
            'Pasta do jogo normalizada de $savedGameDirectory para '
            '$gameDirectory.',
          );
        }
      } else {
        const defaultPath = r'C:\Program Files\Neverness To Everness';
        gameDirectory = (await installer.resolveGameDirectory(
          defaultPath,
        ))?.gameDirectory;
      }
      if (!_isCurrent(operation)) {
        return;
      }
      if (gameDirectory != null) {
        await _detectGamePlatform(operation);
      }

      status = LauncherStatus.loadingManifest;
      _notify();
      loadedManifest = await manifests.load();
      if (!_isCurrent(operation)) {
        return;
      }
      totalBytes = manifest?.totalBytes ?? 0;
      if (loadedManifest != null && gameDirectory != null) {
        final recovery = await installer.recoverAbandoned(
          gameDirectory!,
          manifest!,
        );
        if (!recovery.complete) {
          verification = TranslationVerificationResult(
            status: TranslationInstallationStatus.unverifiable,
            error:
                'Operação abandonada requer diagnóstico: '
                '${recovery.unresolvedPaths.join(', ')}',
          );
        } else {
          await migration.migrateWhenProvable(
            gameDirectory: gameDirectory!,
            loadedManifest: loadedManifest!,
          );
          await _verifyCurrent(operation);
        }
      } else {
        verification = const TranslationVerificationResult(
          status: TranslationInstallationStatus.notInstalled,
        );
      }
      if (!_isCurrent(operation)) {
        return;
      }

      await checkLauncherUpdates();
      if (!_isCurrent(operation)) {
        return;
      }
      if (automaticLauncherUpdates && availableAppUpdate != null) {
        await installLauncherUpdate();
        return;
      }
      status = LauncherStatus.ready;
      await log.info(
        'Launcher inicializado; estado da tradução: '
        '${verification.status.name}.',
      );
      _notify();

      if (autoInstall && gameDirectory != null && _requiresWriteOperation) {
        await installOrUpdate(repair: translationNeedsRepair);
        return;
      }
      if (translationUpdateAvailable &&
          loadedManifest?.isAuthoritative == true &&
          gameDirectory != null) {
        await log.info(
          'Atualização automática comprovada: '
          '$installedVersion -> ${manifest!.translationVersion}.',
        );
        await installOrUpdate();
      }
    } catch (error, stackTrace) {
      if (_isCurrent(operation)) {
        await _setError(
          'Não foi possível iniciar o launcher.',
          error,
          stackTrace,
        );
      }
    }
    _notify();
  }

  bool get _requiresWriteOperation =>
      verification.status == TranslationInstallationStatus.notInstalled ||
      verification.status == TranslationInstallationStatus.installedOutdated ||
      translationNeedsRepair;

  Future<void> chooseGameDirectory() async {
    if (!canChangeGameDirectory) {
      return;
    }
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: 'Selecione a pasta principal de Neverness To Everness',
    );
    if (selected != null) {
      await selectGameDirectory(selected);
    }
  }

  Future<void> selectGameDirectory(String selected) async {
    if (!canChangeGameDirectory) {
      return;
    }

    final candidate = selected.trim();
    final operation = ++_operationGeneration;
    validatingGameDirectory = true;
    rejectedGameDirectory = candidate;
    gameDirectorySelectionError = null;
    _notify();

    GameDirectoryResolution? resolution;
    try {
      resolution = await installer.resolveGameDirectory(candidate);
    } catch (error, stackTrace) {
      if (_isCurrent(operation)) {
        validatingGameDirectory = false;
        gameDirectorySelectionError =
            'Não foi possível verificar a pasta selecionada.';
        await log.error(
          'Falha ao validar o diretório candidato $candidate: '
          '$error\n$stackTrace',
        );
        _notify();
      }
      return;
    }

    if (!_isCurrent(operation)) {
      return;
    }

    if (resolution == null) {
      validatingGameDirectory = false;
      gameDirectorySelectionError =
          'Não foi possível localizar uma instalação completa do NTE. '
          'Selecione a pasta principal do jogo ou a pasta NTEGlobal.';
      _notify();
      return;
    }

    validatingGameDirectory = false;
    rejectedGameDirectory = null;
    gameDirectorySelectionError = null;
    verification = const TranslationVerificationResult.checking();
    preInstallationReport = null;
    gamePlatform = null;
    errorMessage = null;
    status = LauncherStatus.verifying;
    gameDirectory = resolution.gameDirectory;
    _notify();

    await settings.setGameDirectory(gameDirectory!);
    if (resolution.wasAdjusted) {
      await log.info(
        'Pasta selecionada $candidate normalizada para $gameDirectory.',
      );
    }
    await _detectGamePlatform(operation);
    if (loadedManifest != null && _isCurrent(operation)) {
      await _verifyCurrent(operation);
    }
    if (_isCurrent(operation)) {
      status = LauncherStatus.ready;
      _notify();
    }
  }

  Future<void> verifyAgain() async {
    if (isBusy || gameDirectory == null || loadedManifest == null) {
      return;
    }
    final operation = ++_operationGeneration;
    await _verifyCurrent(operation);
    if (_isCurrent(operation)) {
      status = LauncherStatus.ready;
      _notify();
    }
  }

  Future<void> _verifyCurrent(int operation) async {
    final directory = gameDirectory;
    final loaded = loadedManifest;
    if (directory == null || loaded == null) {
      return;
    }
    final directorySnapshot = directory;
    final manifestSnapshot = loaded;
    status = LauncherStatus.verifying;
    verification = const TranslationVerificationResult.checking();
    verifiedFiles = 0;
    verificationTotalFiles = loaded.manifest.files.length;
    currentFile = '';
    _notify();
    final result = await verifier.verify(
      loadedManifest: manifestSnapshot,
      gameDirectory: directorySnapshot,
      isCancelled: () =>
          !_isCurrent(operation) ||
          gameDirectory != directorySnapshot ||
          loadedManifest != manifestSnapshot,
      onProgress: (file, verified, total) {
        if (!_isCurrent(operation) ||
            gameDirectory != directorySnapshot ||
            loadedManifest != manifestSnapshot) {
          return;
        }
        currentFile = file;
        verifiedFiles = verified;
        verificationTotalFiles = total;
        _notify();
      },
    );
    if (!_isCurrent(operation) ||
        gameDirectory != directorySnapshot ||
        loadedManifest != manifestSnapshot) {
      return;
    }
    verification = result;
    currentFile = '';
    if (result.status == TranslationInstallationStatus.notInstalled &&
        persistedInstalledVersion != null) {
      await log.info(
        'Versão persistida $persistedInstalledVersion não foi confirmada '
        'pelo disco e será descartada.',
      );
      await settings.clearInstalledVersion();
      persistedInstalledVersion = null;
    } else if (result.isVerified && result.detectedVersion != null) {
      persistedInstalledVersion = result.detectedVersion;
      await settings.setInstalledVersion(result.detectedVersion!);
    }
    await log.info(
      'Verificação concluída: ${result.status.name}; '
      '${result.validFiles.length} válidos, '
      '${result.missingFiles.length} ausentes, '
      '${result.modifiedFiles.length} modificados.',
    );
  }

  Future<void> installOrUpdate({bool repair = false}) async {
    final selectedManifest = manifest;
    final selectedGameDirectory = gameDirectory;
    final selectedLoadedManifest = loadedManifest;
    if (selectedManifest == null ||
        selectedLoadedManifest == null ||
        selectedGameDirectory == null ||
        isBusy ||
        hasUnmanagedChanges) {
      return;
    }
    if (translationUpdateAvailable && !selectedLoadedManifest.isAuthoritative) {
      await _setError(
        'Atualização bloqueada.',
        const InstallationException(
          'Um manifesto offline não pode provocar atualização ou downgrade.',
        ),
        StackTrace.current,
      );
      _notify();
      return;
    }

    final operation = ++_operationGeneration;
    _cancelRequested = false;
    errorMessage = null;
    currentFile = '';
    receivedBytes = 0;
    totalBytes = selectedManifest.totalBytes;
    preInstallationReport = null;
    status = LauncherStatus.preparing;
    _notify();

    try {
      final report = await preInstallation.run(
        manifest: selectedManifest,
        gameDirectory: selectedGameDirectory,
        downloadDirectory: paths.downloads.path,
      );
      if (!_isCurrent(operation)) {
        return;
      }
      preInstallationReport = report;
      await log.info(
        'Pré-instalação: ${report.passedCount} aprovações, '
        '${report.warningCount} avisos, ${report.failures.length} falhas.',
      );
      if (!report.canProceed) {
        throw InstallationException(report.failureSummary);
      }
      status = LauncherStatus.downloading;
      _notify();
      final stage = await downloads.download(
        selectedManifest,
        onProgress: (received, total, file) {
          if (!_isCurrent(operation)) {
            return;
          }
          receivedBytes = received;
          totalBytes = total;
          currentFile = file;
          _notify();
        },
        isCancelled: () => _cancelRequested || !_isCurrent(operation),
      );
      if (_cancelRequested || !_isCurrent(operation)) {
        throw const DownloadCancelledException();
      }

      status = repair
          ? LauncherStatus.repairing
          : translationUpdateAvailable
          ? LauncherStatus.updating
          : LauncherStatus.installing;
      currentFile = repair
          ? 'Reparando arquivos com segurança'
          : 'Aplicando arquivos com segurança';
      _notify();
      await elevation.ensureWritableOrRestart(
        selectedGameDirectory,
        allowRestart: !autoInstall,
      );
      if (!_isCurrent(operation) ||
          gameDirectory != selectedGameDirectory ||
          loadedManifest != selectedLoadedManifest) {
        throw const InstallationException(
          'O diretório ou o manifesto mudou durante a operação.',
        );
      }
      await installer.install(selectedManifest, stage, selectedGameDirectory);
      persistedInstalledVersion = selectedManifest.translationVersion;
      await settings.setInstalledVersion(selectedManifest.translationVersion);
      await _verifyCurrent(operation);
      if (!translationIsCurrent) {
        throw InstallationException(
          'A validação pós-instalação retornou '
          '${verification.status.name}.',
        );
      }
      receivedBytes = totalBytes;
      currentFile = '';
      status = LauncherStatus.completed;
      await log.info(
        'Operação concluída e verificada para '
        '${selectedManifest.translationVersion}.',
      );
    } on DownloadCancelledException {
      if (_isCurrent(operation)) {
        status = LauncherStatus.ready;
        currentFile = '';
        await log.info('Download cancelado pelo usuário.');
      }
    } catch (error, stackTrace) {
      if (_isCurrent(operation)) {
        await _setError(
          repair
              ? 'Não foi possível reparar a tradução.'
              : 'Não foi possível instalar a tradução.',
          error,
          stackTrace,
        );
      }
    }
    _notify();
  }

  Future<void> repairTranslation() => installOrUpdate(repair: true);

  void cancelDownload() {
    if (status == LauncherStatus.downloading) {
      _cancelRequested = true;
      currentFile = 'Cancelando...';
      _notify();
    }
  }

  Future<void> removeTranslation() async {
    final directory = gameDirectory;
    if (isBusy || !canRemove || directory == null) {
      return;
    }
    final operation = ++_operationGeneration;
    status = LauncherStatus.removing;
    errorMessage = null;
    _notify();
    try {
      final result = await installer.uninstall(directory);
      if (!result.complete) {
        throw InstallationException(
          'Remoção parcial. Arquivos modificados preservados: '
          '${result.preservedModifiedFiles.length}; falhas: '
          '${result.failedFiles.length}. Recibo e backups foram mantidos.',
        );
      }
      await settings.clearInstalledVersion();
      persistedInstalledVersion = null;
      await _verifyCurrent(operation);
      status = LauncherStatus.ready;
    } catch (error, stackTrace) {
      await _verifyCurrent(operation);
      await _setError(
        'Não foi possível remover completamente a tradução.',
        error,
        stackTrace,
      );
    }
    _notify();
  }

  Future<void> launchGame({bool allowInvalidTranslation = false}) async {
    final directory = gameDirectory;
    if (directory == null || isBusy) {
      return;
    }
    final invalid =
        verification.status == TranslationInstallationStatus.incomplete ||
        verification.status == TranslationInstallationStatus.modified ||
        verification.status == TranslationInstallationStatus.unverifiable ||
        verification.status ==
            TranslationInstallationStatus.incompatibleGameBuild;
    if (invalid && !allowInvalidTranslation) {
      errorMessage =
          'A tradução não está íntegra. Repare ou remova a tradução antes '
          'de jogar; você também pode confirmar a abertura por sua conta.';
      status = LauncherStatus.error;
      _notify();
      return;
    }
    try {
      final platform = gamePlatform ?? await gamePlatforms.detect(directory);
      gamePlatform = platform;
      await log.info('Abrindo o jogo pela plataforma ${platform.label}.');
      await gamePlatforms.launch(platform, directory);
      await log.info('Jogo acionado com sucesso; encerrando o launcher.');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      exit(0);
    } catch (error, stackTrace) {
      await _setError('Não foi possível abrir o jogo.', error, stackTrace);
      _notify();
    }
  }

  Future<void> checkLauncherUpdates() async {
    if (checkingAppUpdate || updatingLauncher) {
      return;
    }
    checkingAppUpdate = true;
    _notify();
    try {
      appVersion = await appUpdates.currentVersion();
      availableAppUpdate = await appUpdates.check();
    } catch (error, stackTrace) {
      await log.error(
        'Não foi possível verificar atualizações do launcher.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      checkingAppUpdate = false;
      _notify();
    }
  }

  Future<void> setAutomaticLauncherUpdates(bool value) async {
    automaticLauncherUpdates = value;
    await settings.setAutomaticLauncherUpdates(value);
    _notify();
  }

  Future<void> installLauncherUpdate() async {
    final update = availableAppUpdate;
    if (update == null || updatingLauncher) {
      return;
    }
    updatingLauncher = true;
    appUpdateReceivedBytes = 0;
    appUpdateTotalBytes = update.installerSize;
    errorMessage = null;
    _notify();
    try {
      final installer = await appUpdates.downloadInstaller(
        update,
        onProgress: (received, total) {
          appUpdateReceivedBytes = received;
          appUpdateTotalBytes = total;
          _notify();
        },
      );
      await appUpdates.startInstaller(installer);
      await log.info(
        'Instalador ${update.version} iniciado; encerrando launcher.',
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      exit(0);
    } catch (error, stackTrace) {
      updatingLauncher = false;
      await _setError(
        'Não foi possível atualizar o launcher.',
        error,
        stackTrace,
      );
      _notify();
    }
  }

  Future<void> _detectGamePlatform(int operation) async {
    final directory = gameDirectory;
    if (directory == null) {
      gamePlatform = null;
      return;
    }
    final detected = await gamePlatforms.detect(directory);
    if (_isCurrent(operation) && gameDirectory == directory) {
      gamePlatform = detected;
      await log.info('Plataforma detectada: ${detected.label}.');
    }
  }

  void clearError() {
    errorMessage = null;
    status = LauncherStatus.ready;
    _notify();
  }

  Future<File> exportDiagnostics({bool reveal = true}) async {
    await paths.diagnostics.create(recursive: true);
    final recentLogs = await log.diagnosticExcerpts();
    final payload = {
      'schemaVersion': 2,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'launcherVersion': appVersion,
      'status': status.name,
      'gameDirectory': gameDirectory,
      'platform': gamePlatform?.label,
      'manifestSource': manifestSource?.name,
      'availableTranslationVersion': manifest?.translationVersion,
      'installedTranslationVersion': installedVersion,
      'verificationStatus': verification.status.name,
      'verification': {
        'status': verification.status.name,
        'detectedVersion': verification.detectedVersion,
        'receiptVersion': verification.receiptVersion,
        'validFiles': verification.validFiles,
        'missingFiles': verification.missingFiles,
        'modifiedFiles': verification.modifiedFiles,
        'unverifiableFiles': verification.unverifiableFiles,
        'managedDirectory': verification.managedDirectory,
        'error': verification.error?.toString(),
      },
      'offlineMode': offlineMode,
      'preInstallationChecks': [
        for (final check in preInstallationReport?.checks ?? const [])
          {'id': check.id, 'status': check.status.name, 'detail': check.detail},
      ],
      'lastError': errorMessage,
      'logFiles': [
        paths.logFile.path,
        for (var index = 1; index <= 5; index++) '${paths.logFile.path}.$index',
      ],
      'recentLogs': recentLogs,
    };
    final temporary = File('${paths.diagnosticFile.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    if (await paths.diagnosticFile.exists()) {
      await paths.diagnosticFile.delete();
    }
    await temporary.rename(paths.diagnosticFile.path);
    await log.info('Diagnóstico exportado para ${paths.diagnosticFile.path}.');
    if (reveal && Platform.isWindows) {
      await Process.start('explorer.exe', [
        '/select,',
        paths.diagnosticFile.path,
      ]);
    }
    return paths.diagnosticFile;
  }

  Future<void> _setError(
    String context,
    Object error,
    StackTrace stackTrace,
  ) async {
    errorMessage = '$context\n${_friendlyError(error)}';
    status = LauncherStatus.error;
    await log.error(context, error: error, stackTrace: stackTrace);
  }

  String _friendlyError(Object error) {
    if (error is HandshakeException) {
      return 'Falha ao validar a conexão segura. Consulte o log.';
    }
    if (error is SocketException) {
      return 'Sem conexão com a internet ou endereço indisponível.';
    }
    if (error is HttpException) {
      return error.message;
    }
    return error.toString();
  }

  bool _isCurrent(int operation) =>
      !_disposed && operation == _operationGeneration;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _operationGeneration++;
    super.dispose();
  }
}
