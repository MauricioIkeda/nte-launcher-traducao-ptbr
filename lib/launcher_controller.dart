import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'core/app_paths.dart';
import 'core/launcher_log.dart';
import 'models/translation_manifest.dart';
import 'services/download_service.dart';
import 'services/elevation_service.dart';
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
    required this.manifests,
    required this.downloads,
    required this.elevation,
    required this.installer,
    required this.settings,
    this.autoInstall = false,
  });

  final AppPaths paths;
  final LauncherLog log;
  final ManifestRepository manifests;
  final DownloadService downloads;
  final ElevationService elevation;
  final InstallationService installer;
  final SettingsService settings;
  final bool autoInstall;

  LauncherStatus status = LauncherStatus.starting;
  TranslationManifest? manifest;
  String? gameDirectory;
  String? installedVersion;
  String? errorMessage;
  String currentFile = '';
  int receivedBytes = 0;
  int totalBytes = 0;
  bool _cancelRequested = false;

  double get progress =>
      totalBytes <= 0 ? 0 : (receivedBytes / totalBytes).clamp(0, 1);
  bool get isBusy =>
      status == LauncherStatus.downloading ||
      status == LauncherStatus.installing ||
      status == LauncherStatus.removing;
  bool get canInstall => !isBusy && manifest != null && gameDirectory != null;
  bool get isInstalled =>
      installedVersion != null && installedVersion!.isNotEmpty;

  Future<void> initialize() async {
    status = LauncherStatus.starting;
    notifyListeners();
    try {
      gameDirectory = await settings.getGameDirectory();
      installedVersion = await settings.getInstalledVersion();
      if (gameDirectory == null ||
          !await installer.isValidGameDirectory(gameDirectory!)) {
        const defaultPath = r'C:\Program Files\Neverness To Everness';
        gameDirectory = await installer.isValidGameDirectory(defaultPath)
            ? defaultPath
            : null;
      }
      manifest = await manifests.load();
      totalBytes = manifest!.totalBytes;
      status = LauncherStatus.ready;
      await log.info('Launcher inicializado.');
      notifyListeners();
      if (autoInstall && gameDirectory != null) {
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
    if (directory == null || isBusy) {
      return;
    }
    try {
      await Process.start(
        p.join(directory, InstallationService.gameExecutable),
        const [],
        workingDirectory: directory,
        mode: ProcessStartMode.detached,
      );
    } catch (error, stackTrace) {
      await _setError('Não foi possível abrir o jogo.', error, stackTrace);
      notifyListeners();
    }
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
