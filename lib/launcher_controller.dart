import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'core/app_paths.dart';
import 'core/launcher_log.dart';
import 'models/app_update_manifest.dart';
import 'models/translation_manifest.dart';
import 'services/app_update_service.dart';
import 'services/download_service.dart';
import 'services/elevation_service.dart';
import 'services/game_platform_service.dart';
import 'services/installation_service.dart';
import 'services/manifest_repository.dart';
import 'services/settings_service.dart';

enum LauncherStatus {
  starting,
  ready,
  downloading,
  installing,
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
    this.autoInstall = false,
  });

  final AppPaths paths;
  final LauncherLog log;
  final AppUpdateService appUpdates;
  final ManifestRepository manifests;
  final DownloadService downloads;
  final ElevationService elevation;
  final GamePlatformService gamePlatforms;
  final InstallationService installer;
  final LauncherSettings settings;
  final bool autoInstall;

  LauncherStatus status = LauncherStatus.starting;
  TranslationManifest? manifest;
  String? gameDirectory;
  GamePlatformInfo? gamePlatform;
  String? installedVersion;
  String appVersion = '...';
  AppUpdateManifest? availableAppUpdate;
  bool checkingAppUpdate = false;
  bool updatingLauncher = false;
  bool automaticLauncherUpdates = false;
  bool officialAutoplay = true;
  int appUpdateReceivedBytes = 0;
  int appUpdateTotalBytes = 0;
  String? errorMessage;
  String currentFile = '';
  int receivedBytes = 0;
  int totalBytes = 0;
  bool _cancelRequested = false;

  double get progress =>
      totalBytes <= 0 ? 0 : (receivedBytes / totalBytes).clamp(0, 1);
  bool get isBusy =>
      updatingLauncher ||
      status == LauncherStatus.starting ||
      status == LauncherStatus.downloading ||
      status == LauncherStatus.installing ||
      status == LauncherStatus.removing;
  bool get canInstall => !isBusy && manifest != null && gameDirectory != null;
  bool get isInstalled =>
      installedVersion != null && installedVersion!.isNotEmpty;
  bool get translationIsCurrent =>
      isInstalled &&
      manifest != null &&
      installedVersion == manifest!.translationVersion;
  bool get translationUpdateAvailable =>
      isInstalled &&
      manifest != null &&
      installedVersion != manifest!.translationVersion;

  Future<void> initialize() async {
    status = LauncherStatus.starting;
    notifyListeners();
    try {
      gameDirectory = await settings.getGameDirectory();
      installedVersion = await settings.getInstalledVersion();
      automaticLauncherUpdates = await settings.getAutomaticLauncherUpdates();
      officialAutoplay = await settings.getOfficialAutoplay();
      if (gameDirectory == null ||
          !await installer.isValidGameDirectory(gameDirectory!)) {
        const defaultPath = r'C:\Program Files\Neverness To Everness';
        gameDirectory = await installer.isValidGameDirectory(defaultPath)
            ? defaultPath
            : null;
      }
      if (gameDirectory != null) {
        await _detectGamePlatform();
      }
      await _removeLegacyTranslationIfPresent();
      manifest = await manifests.load();
      totalBytes = manifest?.totalBytes ?? 0;
      await log.info('Launcher inicializado.');
      await checkLauncherUpdates();
      if (automaticLauncherUpdates && availableAppUpdate != null) {
        await installLauncherUpdate();
        return;
      }
      status = LauncherStatus.ready;
      if (autoInstall && gameDirectory != null) {
        await installOrUpdate();
        return;
      }
      if (translationUpdateAvailable && gameDirectory != null) {
        await log.info(
          'Atualização automática da tradução: '
          '$installedVersion -> ${manifest!.translationVersion}.',
        );
        await installOrUpdate();
        return;
      }
    } catch (error, stackTrace) {
      await _setError(
        'Não foi possível iniciar o launcher.',
        error,
        stackTrace,
      );
    }
    notifyListeners();
  }

  Future<void> _removeLegacyTranslationIfPresent() async {
    final version = installedVersion;
    if (version == null || version.isEmpty || version.startsWith('nte-auto-')) {
      return;
    }
    if (await installer.hasReceipt()) {
      await installer.uninstall();
      await log.info(
        'Pacote legado $version removido antes da migração automática.',
      );
    } else {
      await log.info(
        'Registro legado $version descartado; não havia recibo de instalação.',
      );
    }
    await settings.clearInstalledVersion();
    installedVersion = null;
  }

  Future<void> chooseGameDirectory() async {
    if (isBusy) {
      return;
    }
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: 'Selecione a pasta principal de Neverness To Everness',
    );
    if (selected == null) {
      return;
    }
    if (!await installer.isValidGameDirectory(selected)) {
      errorMessage = 'A pasta selecionada não contém NTEGlobalLauncher.exe.';
      status = LauncherStatus.error;
      notifyListeners();
      return;
    }
    gameDirectory = selected;
    await _detectGamePlatform();
    await settings.setGameDirectory(selected);
    errorMessage = null;
    status = LauncherStatus.ready;
    notifyListeners();
  }

  Future<void> installOrUpdate() async {
    final selectedManifest = manifest;
    final selectedGameDirectory = gameDirectory;
    if (selectedManifest == null || selectedGameDirectory == null || isBusy) {
      return;
    }

    _cancelRequested = false;
    errorMessage = null;
    currentFile = '';
    receivedBytes = 0;
    totalBytes = selectedManifest.totalBytes;
    status = LauncherStatus.downloading;
    notifyListeners();

    try {
      final stage = await downloads.download(
        selectedManifest,
        onProgress: (received, total, file) {
          receivedBytes = received;
          totalBytes = total;
          currentFile = file;
          notifyListeners();
        },
        isCancelled: () => _cancelRequested,
      );
      if (_cancelRequested) {
        throw const DownloadCancelledException();
      }

      status = LauncherStatus.installing;
      currentFile = 'Aplicando arquivos com segurança';
      notifyListeners();
      await elevation.ensureWritableOrRestart(
        selectedGameDirectory,
        allowRestart: !autoInstall,
      );
      await installer.install(selectedManifest, stage, selectedGameDirectory);
      await settings.setInstalledVersion(selectedManifest.translationVersion);
      installedVersion = selectedManifest.translationVersion;
      receivedBytes = totalBytes;
      currentFile = '';
      status = LauncherStatus.completed;
      await log.info(
        'Operação concluída para ${selectedManifest.translationVersion}.',
      );
    } on DownloadCancelledException {
      status = LauncherStatus.ready;
      currentFile = '';
      await log.info('Download cancelado pelo usuário.');
    } catch (error, stackTrace) {
      await _setError(
        'Não foi possível instalar a tradução.',
        error,
        stackTrace,
      );
    }
    notifyListeners();
  }

  void cancelDownload() {
    if (status == LauncherStatus.downloading) {
      _cancelRequested = true;
      currentFile = 'Cancelando...';
      notifyListeners();
    }
  }

  Future<void> removeTranslation() async {
    if (isBusy || !isInstalled) {
      return;
    }
    status = LauncherStatus.removing;
    errorMessage = null;
    notifyListeners();
    try {
      await installer.uninstall();
      await settings.clearInstalledVersion();
      installedVersion = null;
      status = LauncherStatus.ready;
    } catch (error, stackTrace) {
      await _setError(
        'Não foi possível remover a tradução.',
        error,
        stackTrace,
      );
    }
    notifyListeners();
  }

  Future<void> launchGame() async {
    final directory = gameDirectory;
    if (directory == null || isBusy || translationUpdateAvailable) {
      return;
    }
    try {
      final platform = gamePlatform ?? await gamePlatforms.detect(directory);
      gamePlatform = platform;
      await log.info('Abrindo o jogo pela plataforma ${platform.label}.');
      await gamePlatforms.launch(
        platform,
        directory,
        officialAutoplay: officialAutoplay,
      );
      await log.info('Jogo acionado com sucesso; encerrando o launcher.');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      exit(0);
    } catch (error, stackTrace) {
      await _setError('Não foi possível abrir o jogo.', error, stackTrace);
      notifyListeners();
    }
  }

  Future<void> checkLauncherUpdates() async {
    if (checkingAppUpdate || updatingLauncher) {
      return;
    }
    checkingAppUpdate = true;
    notifyListeners();
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
      notifyListeners();
    }
  }

  Future<void> setAutomaticLauncherUpdates(bool value) async {
    automaticLauncherUpdates = value;
    await settings.setAutomaticLauncherUpdates(value);
    notifyListeners();
  }

  Future<void> setOfficialAutoplay(bool value) async {
    officialAutoplay = value;
    await settings.setOfficialAutoplay(value);
    notifyListeners();
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
    notifyListeners();
    try {
      final installer = await appUpdates.downloadInstaller(
        update,
        onProgress: (received, total) {
          appUpdateReceivedBytes = received;
          appUpdateTotalBytes = total;
          notifyListeners();
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
      notifyListeners();
    }
  }

  Future<void> _detectGamePlatform() async {
    final directory = gameDirectory;
    if (directory == null) {
      gamePlatform = null;
      return;
    }
    gamePlatform = await gamePlatforms.detect(directory);
    await log.info('Plataforma detectada: ${gamePlatform!.label}.');
  }

  void clearError() {
    errorMessage = null;
    status = LauncherStatus.ready;
    notifyListeners();
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
}
