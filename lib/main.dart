import 'dart:ui';

import 'package:flutter/material.dart';

import 'core/app_paths.dart';
import 'core/launcher_log.dart';
import 'core/trusted_http_client.dart';
import 'launcher_controller.dart';
import 'services/app_update_service.dart';
import 'services/download_service.dart';
import 'services/elevation_service.dart';
import 'services/game_platform_service.dart';
import 'services/installation_service.dart';
import 'services/manifest_repository.dart';
import 'services/settings_service.dart';

const _cyan = Color(0xFF3EE8FF);
const _coral = Color(0xFFFF657F);
const _ink = Color(0xFF07101C);
const _muted = Color(0xFF9AA9BC);

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await TrustedHttpClientFactory.initialize();
  final paths = await AppPaths.create();
  final log = LauncherLog(paths.logFile);
  final controller = LauncherController(
    paths: paths,
    log: log,
    appUpdates: AppUpdateService(paths, log),
    manifests: ManifestRepository(paths, log),
    downloads: DownloadService(paths, log),
    elevation: ElevationService(log),
    gamePlatforms: GamePlatformService(),
    installer: InstallationService(paths, log),
    settings: SettingsService(),
    autoInstall: arguments.contains('--install'),
  );
  runApp(NteLauncherApp(controller: controller));
}

class NteLauncherApp extends StatelessWidget {
  const NteLauncherApp({super.key, required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NTE Tradução PT-BR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Segoe UI',
        colorScheme: const ColorScheme.dark(
          primary: _cyan,
          secondary: _coral,
          surface: Color(0xFF101C2A),
          error: Color(0xFFFF6B81),
        ),
        scaffoldBackgroundColor: _ink,
        splashFactory: InkSparkle.splashFactory,
        tooltipTheme: const TooltipThemeData(
          decoration: BoxDecoration(
            color: Color(0xEE101C2A),
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          textStyle: TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      home: LauncherPage(controller: controller),
    );
  }
}

class LauncherPage extends StatefulWidget {
  const LauncherPage({super.key, required this.controller});

  final LauncherController controller;

  @override
  State<LauncherPage> createState() => _LauncherPageState();
}

class _LauncherPageState extends State<LauncherPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              const _HeroBackground(),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 960;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 24 : 42,
                        24,
                        compact ? 24 : 42,
                        22,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TopBar(controller: widget.controller),
                          const Spacer(),
                          _HeroCopy(compact: compact),
                          SizedBox(height: compact ? 18 : 24),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: compact ? 640 : 700,
                            ),
                            child: _UpdatePanel(controller: widget.controller),
                          ),
                          const SizedBox(height: 14),
                          _Footer(controller: widget.controller),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroBackground extends StatelessWidget {
  const _HeroBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/launcher_city_hero.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [0, .38, .72, 1],
              colors: [
                Color(0xD907101C),
                Color(0x9907101C),
                Color(0x1A07101C),
                Color(0x2607101C),
              ],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, .52, 1],
              colors: [
                Color(0x4D020915),
                Colors.transparent,
                Color(0xD9020915),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _BrandMark(),
        const SizedBox(width: 14),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'NTE',
                  style: TextStyle(
                    fontSize: 25,
                    height: .9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                SizedBox(width: 9),
                Text(
                  'PT-BR',
                  style: TextStyle(
                    color: _cyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            SizedBox(height: 5),
            Text(
              'LAUNCHER COMUNITÁRIO  //  EIBON NETWORK',
              style: TextStyle(
                color: Color(0xFFB7C4D4),
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
        const Spacer(),
        _LiveStatus(controller: controller),
        const SizedBox(width: 10),
        _SquareAction(
          tooltip: 'Configurações e atualizações',
          icon: Icons.settings_outlined,
          onPressed: controller.isBusy
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (_) => _SettingsDialog(controller: controller),
                ),
        ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -.28,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _cyan.withValues(alpha: .72)),
              ),
            ),
          ),
          Transform.rotate(
            angle: .42,
            child: Container(
              width: 33,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _coral.withValues(alpha: .75)),
              ),
            ),
          ),
          const Text(
            'N',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveStatus extends StatelessWidget {
  const _LiveStatus({required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    final online =
        controller.manifest != null &&
        controller.status != LauncherStatus.error;
    return _GlassSurface(
      radius: 99,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? const Color(0xFF73F0B3) : _coral,
              boxShadow: [
                BoxShadow(
                  color: (online ? const Color(0xFF73F0B3) : _coral).withValues(
                    alpha: .55,
                  ),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            online ? 'MANIFESTO VERIFICADO' : 'VERIFICANDO REDE',
            style: const TextStyle(
              color: Color(0xFFD8E3EF),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 28, height: 2, color: _coral),
            const SizedBox(width: 10),
            const Text(
              'ANOMALIA LOCALIZADA  //  HETHEREAU',
              style: TextStyle(
                color: Color(0xFFE5B8C3),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'A CIDADE AGORA\nFALA PORTUGUÊS.',
          style: TextStyle(
            fontSize: compact ? 34 : 43,
            height: .96,
            fontWeight: FontWeight.w900,
            letterSpacing: -.8,
            shadows: const [
              Shadow(
                color: Color(0xAA020712),
                blurRadius: 18,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Tradução comunitária com instalação segura, verificável e reversível.',
          style: TextStyle(
            color: Color(0xFFD0DAE6),
            fontSize: 13,
            letterSpacing: .15,
          ),
        ),
      ],
    );
  }
}

class _UpdatePanel extends StatelessWidget {
  const _UpdatePanel({required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    final manifest = controller.manifest;
    final availableVersion = manifest?.translationVersion;
    final translationIsCurrent =
        controller.isInstalled &&
        availableVersion != null &&
        controller.installedVersion == availableVersion;
    final actionLabel = !controller.isInstalled
        ? 'INSTALAR TRADUÇÃO'
        : translationIsCurrent
        ? 'JOGAR PELA ${controller.gamePlatform?.label.toUpperCase() ?? 'PLATAFORMA DETECTADA'}'
        : 'ATUALIZAR PARA v${availableVersion ?? '...'}';
    final actionIcon = translationIsCurrent
        ? Icons.play_arrow_rounded
        : Icons.download_done_rounded;
    final actionEnabled = translationIsCurrent
        ? controller.gameDirectory != null && !controller.isBusy
        : controller.canInstall;
    final action = translationIsCurrent
        ? controller.launchGame
        : controller.installOrUpdate;
    return _GlassSurface(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(20, 17, 17, 17),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'PACOTE DE IDIOMA',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.7,
                ),
              ),
              const SizedBox(width: 10),
              _VersionTag(
                label: manifest == null
                    ? 'SINCRONIZANDO'
                    : 'v${manifest.translationVersion}',
              ),
              const Spacer(),
              const Icon(Icons.shield_outlined, color: _cyan, size: 16),
              const SizedBox(width: 6),
              const Text(
                'SHA-256',
                style: TextStyle(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          if (controller.availableAppUpdate != null ||
              controller.updatingLauncher) ...[
            const SizedBox(height: 12),
            _LauncherUpdateBanner(controller: controller),
          ],
          const SizedBox(height: 13),
          _FolderField(controller: controller),
          const SizedBox(height: 13),
          _ProgressArea(controller: controller),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 10),
            _ErrorMessage(message: controller.errorMessage!),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (controller.status == LauncherStatus.downloading)
                Expanded(
                  child: _SecondaryButton(
                    label: 'CANCELAR DOWNLOAD',
                    icon: Icons.close,
                    onPressed: controller.cancelDownload,
                  ),
                )
              else ...[
                if (controller.isInstalled) ...[
                  SizedBox(
                    width: 190,
                    child: _SecondaryButton(
                      label: 'REMOVER TRADUÇÃO',
                      icon: Icons.delete_outline_rounded,
                      onPressed: controller.isBusy
                          ? null
                          : controller.removeTranslation,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: _PrimaryActionButton(
                    label: actionLabel,
                    icon: actionIcon,
                    enabled: actionEnabled,
                    onPressed: action,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LauncherUpdateBanner extends StatelessWidget {
  const _LauncherUpdateBanner({required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    final update = controller.availableAppUpdate;
    final progress = controller.appUpdateTotalBytes <= 0
        ? 0.0
        : controller.appUpdateReceivedBytes / controller.appUpdateTotalBytes;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: _coral.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _coral.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update_alt_rounded, color: _coral, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.updatingLauncher
                      ? 'BAIXANDO ATUALIZAÇÃO DO LAUNCHER'
                      : 'NOVA VERSÃO DISPONÍVEL  //  v${update?.version}',
                  style: const TextStyle(
                    color: Color(0xFFFFC7D0),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 3),
                if (controller.updatingLauncher)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: const Color(0x55334455),
                      valueColor: const AlwaysStoppedAnimation(_coral),
                    ),
                  )
                else
                  Text(
                    update?.releaseNotes.isEmpty == false
                        ? update!.releaseNotes
                        : 'Atualização verificada e pronta para instalar.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 9),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (!controller.updatingLauncher)
            TextButton(
              onPressed: controller.installLauncherUpdate,
              style: TextButton.styleFrom(
                foregroundColor: _coral,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
              ),
              child: const Text(
                'ATUALIZAR AGORA',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog({required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: _GlassSurface(
              radius: 18,
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune_rounded, color: _cyan),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'CONFIGURAÇÕES',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0x66101A28),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: const Color(0x554B657D)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.autorenew_rounded,
                          color: _coral,
                          size: 20,
                        ),
                        const SizedBox(width: 11),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ATUALIZAÇÕES AUTOMÁTICAS',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .8,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Baixar e instalar ao abrir quando houver '
                                'uma versão nova.',
                                style: TextStyle(color: _muted, fontSize: 9),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: controller.automaticLauncherUpdates,
                          onChanged: controller.setAutomaticLauncherUpdates,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 13),
                  OutlinedButton.icon(
                    onPressed: controller.checkingAppUpdate
                        ? null
                        : controller.checkLauncherUpdates,
                    icon: controller.checkingAppUpdate
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 17),
                    label: Text(
                      controller.checkingAppUpdate
                          ? 'VERIFICANDO...'
                          : 'VERIFICAR AGORA  //  v${controller.appVersion}',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Os instaladores são baixados por HTTPS e só executados '
                    'após a validação de tamanho e SHA-256.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, fontSize: 9),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FolderField extends StatelessWidget {
  const _FolderField({required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: controller.isBusy ? null : controller.chooseGameDirectory,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x78101A28),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x554B657D)),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder_open_rounded, color: _cyan, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DIRETÓRIO DO JOGO',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      controller.gameDirectory ??
                          'Clique para localizar NTEGlobalLauncher.exe',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: controller.gameDirectory == null
                            ? const Color(0xFFBFCCD9)
                            : Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (controller.gamePlatform != null) ...[
                const SizedBox(width: 8),
                _PlatformTag(info: controller.gamePlatform!),
              ],
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF8190A2),
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlatformTag extends StatelessWidget {
  const _PlatformTag({required this.info});

  final GamePlatformInfo info;

  @override
  Widget build(BuildContext context) {
    final icon = switch (info.platform) {
      GamePlatform.epicGames => Icons.storefront_rounded,
      GamePlatform.steam => Icons.sports_esports_rounded,
      GamePlatform.official => Icons.public_rounded,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x7A243448),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFC6D3E1), size: 12),
          const SizedBox(width: 5),
          Text(
            info.label,
            style: const TextStyle(
              color: Color(0xFFC6D3E1),
              fontSize: 7,
              fontWeight: FontWeight.w900,
              letterSpacing: .8,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressArea extends StatelessWidget {
  const _ProgressArea({required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Icon(
              _statusIcon(controller.status),
              color: _statusColor(controller.status),
              size: 15,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                _statusText(controller),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFD8E2EC),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${(controller.progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                color: _cyan,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: controller.status == LauncherStatus.starting
                ? null
                : controller.progress,
            minHeight: 4,
            backgroundColor: const Color(0x70334455),
            valueColor: const AlwaysStoppedAnimation(_cyan),
          ),
        ),
      ],
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0x993A111A),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _coral.withValues(alpha: .35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: _coral, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              message,
              maxLines: 3,
              style: const TextStyle(color: Color(0xFFFFC3CC), fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        elevation: 8,
        shadowColor: _cyan.withValues(alpha: .32),
        backgroundColor: _cyan,
        foregroundColor: const Color(0xFF03131A),
        disabledBackgroundColor: const Color(0xFF344652),
        disabledForegroundColor: const Color(0xFF82919D),
        minimumSize: const Size.fromHeight(47),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 20),
        ],
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFFFC1CB),
        side: const BorderSide(color: Color(0x88FF657F)),
        minimumSize: const Size.fromHeight(47),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          color: Color(0xFFFFC857),
          size: 14,
        ),
        const SizedBox(width: 7),
        const Expanded(
          child: Text(
            'MOD NÃO OFICIAL  •  USE POR SUA CONTA E RISCO',
            style: TextStyle(
              color: Color(0xFF98A8BA),
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Tooltip(
          message: controller.paths.logFile.path,
          child: const Row(
            children: [
              Icon(
                Icons.description_outlined,
                color: Color(0xFF98A8BA),
                size: 13,
              ),
              SizedBox(width: 5),
              Text(
                'LOG TÉCNICO',
                style: TextStyle(
                  color: Color(0xFF98A8BA),
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    required this.child,
    required this.padding,
    this.radius = 16,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: const Color(0xB30A1421),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0x4D9DC8DC)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x6601060D),
                blurRadius: 30,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _VersionTag extends StatelessWidget {
  const _VersionTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _cyan.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: _cyan.withValues(alpha: .35)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _cyan,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: .8,
        ),
      ),
    );
  }
}

class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filled(
        onPressed: onPressed,
        icon: Icon(icon, size: 23),
        style: IconButton.styleFrom(
          fixedSize: const Size(42, 42),
          backgroundColor: const Color(0xD9E7F8FB),
          foregroundColor: const Color(0xFF07141B),
          disabledBackgroundColor: const Color(0x6633414F),
          disabledForegroundColor: const Color(0xFF798693),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

String _statusText(LauncherController controller) {
  return switch (controller.status) {
    LauncherStatus.starting => 'Sincronizando com a rede Eibon...',
    LauncherStatus.ready =>
      controller.isInstalled
          ? 'Tradução v${controller.installedVersion} instalada'
          : 'Sistema pronto para receber a tradução',
    LauncherStatus.downloading => 'Baixando ${controller.currentFile}',
    LauncherStatus.installing => 'Aplicando arquivos com rollback protegido...',
    LauncherStatus.completed => 'Tradução instalada com sucesso',
    LauncherStatus.removing => 'Restaurando os arquivos originais...',
    LauncherStatus.error => 'Operação interrompida — consulte os detalhes',
  };
}

IconData _statusIcon(LauncherStatus status) {
  return switch (status) {
    LauncherStatus.starting => Icons.sync_rounded,
    LauncherStatus.ready => Icons.radio_button_checked,
    LauncherStatus.downloading => Icons.downloading_rounded,
    LauncherStatus.installing => Icons.auto_fix_high_rounded,
    LauncherStatus.completed => Icons.verified_rounded,
    LauncherStatus.removing => Icons.settings_backup_restore_rounded,
    LauncherStatus.error => Icons.error_outline_rounded,
  };
}

Color _statusColor(LauncherStatus status) {
  return switch (status) {
    LauncherStatus.error => _coral,
    LauncherStatus.completed => const Color(0xFF73F0B3),
    _ => _cyan,
  };
}
