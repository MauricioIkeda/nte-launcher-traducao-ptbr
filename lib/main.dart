import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

const _cyan = Color(0xFF35D8F1);
const _coral = Color(0xFFFF4F86);
const _yellow = Color(0xFFFFD84D);
const _green = Color(0xFF69E09D);
const _ink = Color(0xFF07182B);
const _muted = Color(0xFFA9B9C9);

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
      title: 'NTE Launcher Tradução PT-BR',
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
                    final compact = constraints.maxWidth < 980;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 22 : 32,
                        18,
                        compact ? 22 : 32,
                        16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TopBar(controller: widget.controller),
                          const SizedBox(height: 18),
                          Expanded(
                            child: compact
                                ? Align(
                                    alignment: Alignment.bottomCenter,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 680,
                                      ),
                                      child: _UpdatePanel(
                                        controller: widget.controller,
                                      ),
                                    ),
                                  )
                                : Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Expanded(
                                        child: Align(
                                          alignment: Alignment.bottomLeft,
                                          child: _HeroCopy(compact: false),
                                        ),
                                      ),
                                      const SizedBox(width: 34),
                                      SizedBox(
                                        width: 510,
                                        child: _UpdatePanel(
                                          controller: widget.controller,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 12),
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
              stops: [0, .28, .58, 1],
              colors: [
                Color(0x5C07182B),
                Color(0x1A07182B),
                Color(0x2607182B),
                Color(0xB807182B),
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
                Color(0x7307182B),
                Colors.transparent,
                Color(0xD907182B),
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
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NTE LAUNCHER',
              style: TextStyle(
                fontSize: 20,
                height: .95,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'TRADUÇÃO PT-BR  •  PROJETO COMUNITÁRIO',
              style: TextStyle(
                color: _yellow,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.25,
              ),
            ),
          ],
        ),
        const Spacer(),
        _LiveStatus(controller: controller),
        const SizedBox(width: 10),
        _TopAction(
          label: 'CONFIGURAÇÕES',
          icon: Icons.tune_rounded,
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
    return Container(
      width: 54,
      height: 54,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _yellow,
        border: Border.all(color: Colors.white.withValues(alpha: .78)),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 14)],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/app_icon.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
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
              color: online ? _green : _coral,
              boxShadow: [
                BoxShadow(
                  color: (online ? _green : _coral).withValues(alpha: .55),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            online ? 'SERVIÇO ONLINE' : 'CONECTANDO',
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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 32, height: 3, color: _yellow),
            const SizedBox(width: 10),
            const Text(
              'TRADUÇÃO COMUNITÁRIA  //  PT-BR',
              style: TextStyle(
                color: Color(0xFFFFEBA1),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'NTE EM\nPORTUGUÊS.',
          style: TextStyle(
            fontSize: compact ? 32 : 40,
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
          'Instale, mantenha atualizado e jogue em poucos cliques.',
          style: TextStyle(
            color: Color(0xFFF0F5F8),
            fontSize: 13,
            height: 1.45,
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
    final actionLabel = manifest == null
        ? 'AGUARDANDO PRIMEIRA TRADUÇÃO'
        : !controller.isInstalled
        ? 'INSTALAR TRADUÇÃO'
        : translationIsCurrent
        ? 'JOGAR AGORA  •  ${controller.gamePlatform?.label.toUpperCase() ?? 'NTE'}'
        : 'ATUALIZAR TRADUÇÃO  •  v${availableVersion ?? '...'}';
    final actionIcon = manifest == null
        ? Icons.hourglass_top_rounded
        : translationIsCurrent
        ? Icons.play_arrow_rounded
        : Icons.download_done_rounded;
    final actionEnabled = manifest == null
        ? false
        : translationIsCurrent
        ? controller.gameDirectory != null && !controller.isBusy
        : controller.canInstall;
    final VoidCallback? action = manifest == null
        ? null
        : translationIsCurrent
        ? () => controller.launchGame()
        : () => controller.installOrUpdate();
    return _GlassSurface(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(20, 19, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CENTRAL DO LAUNCHER',
                      style: TextStyle(
                        color: _yellow,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Tradução PT-BR',
                      style: TextStyle(
                        fontSize: 22,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      controller.isInstalled
                          ? 'Instalada no seu jogo e pronta para usar'
                          : 'Localize o jogo e instale o pacote de idioma',
                      style: const TextStyle(color: _muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _VersionTag(
                    label: manifest == null
                        ? 'SEM VERSÃO PUBLICADA'
                        : 'PACOTE v${manifest.translationVersion}',
                  ),
                  const SizedBox(height: 7),
                  _InstallStateTag(
                    installed: controller.isInstalled,
                    current: translationIsCurrent,
                  ),
                ],
              ),
            ],
          ),
          if (controller.availableAppUpdate != null ||
              controller.updatingLauncher) ...[
            const SizedBox(height: 14),
            _LauncherUpdateBanner(controller: controller),
          ],
          const SizedBox(height: 14),
          _FolderField(controller: controller),
          const SizedBox(height: 12),
          _ProgressArea(controller: controller),
          if (controller.errorMessage != null) ...[
            const SizedBox(height: 10),
            _ErrorMessage(message: controller.errorMessage!),
          ],
          const SizedBox(height: 12),
          const _RiskNotice(),
          const SizedBox(height: 12),
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
                    width: 170,
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
                    onPressed: action ?? () {},
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

class _InstallStateTag extends StatelessWidget {
  const _InstallStateTag({required this.installed, required this.current});

  final bool installed;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = !installed
        ? ('NÃO INSTALADA', _yellow, Icons.download_outlined)
        : current
        ? ('ATUALIZADA', _green, Icons.check_circle_outline_rounded)
        : ('ATUALIZAÇÃO DISPONÍVEL', _yellow, Icons.update_rounded);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 7,
            fontWeight: FontWeight.w900,
            letterSpacing: .7,
          ),
        ),
      ],
    );
  }
}

class _RiskNotice extends StatelessWidget {
  const _RiskNotice();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => const _RiskDialog(),
        ),
        borderRadius: BorderRadius.circular(11),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(11, 9, 8, 9),
          decoration: BoxDecoration(
            color: _yellow.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: _yellow.withValues(alpha: .42)),
          ),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: _yellow, size: 19),
              SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TRADUÇÃO NÃO OFICIAL  •  EXISTE RISCO À CONTA',
                      style: TextStyle(
                        color: Color(0xFFFFE99A),
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .55,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'O uso pode resultar em punição. Leia antes de instalar.',
                      style: TextStyle(color: Color(0xFFD8E1E9), fontSize: 8),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFFFE99A),
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RiskDialog extends StatelessWidget {
  const _RiskDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: _GlassSurface(
          radius: 20,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.gpp_maybe_outlined, color: _yellow, size: 26),
                  SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ANTES DE CONTINUAR',
                          style: TextStyle(
                            color: _yellow,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.3,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Entenda os riscos da tradução',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const _RiskBullet(
                text:
                    'Este launcher e a tradução são projetos comunitários, '
                    'sem vínculo com os responsáveis pelo jogo.',
              ),
              const _RiskBullet(
                text:
                    'Qualquer modificação pode contrariar os termos do jogo '
                    'e resultar em advertência, suspensão ou banimento.',
              ),
              const _RiskBullet(
                text:
                    'Atualizações do jogo podem tornar a tradução '
                    'temporariamente incompatível.',
              ),
              const _RiskBullet(
                text:
                    'O launcher confere os arquivos e preserva os originais, '
                    'mas isso não elimina o risco para a conta.',
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_rounded),
                label: const Text('ENTENDI E QUERO CONTINUAR'),
                style: FilledButton.styleFrom(
                  backgroundColor: _yellow,
                  foregroundColor: _ink,
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RiskBullet extends StatelessWidget {
  const _RiskBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.circle, color: _coral, size: 7),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFFDDE6EE),
                fontSize: 11,
                height: 1.35,
              ),
            ),
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
                    'Toda atualização é conferida antes de ser instalada.',
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
                      'LOCALIZAÇÃO DO JOGO  •  CLIQUE PARA ALTERAR',
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
              const SizedBox(width: 7),
              const Icon(Icons.chevron_right_rounded, color: _yellow, size: 19),
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
    final progressLabel = switch (controller.status) {
      LauncherStatus.starting => 'CONECTANDO',
      LauncherStatus.downloading ||
      LauncherStatus.installing ||
      LauncherStatus.removing =>
        '${(controller.progress * 100).toStringAsFixed(0)}%',
      LauncherStatus.completed => 'CONCLUÍDO',
      LauncherStatus.error => 'ATENÇÃO',
      LauncherStatus.ready => 'PRONTO',
    };
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
              progressLabel,
              style: TextStyle(
                color: _statusColor(controller.status),
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
        shadowColor: _yellow.withValues(alpha: .3),
        backgroundColor: _yellow,
        foregroundColor: const Color(0xFF03131A),
        disabledBackgroundColor: const Color(0xFF344652),
        disabledForegroundColor: const Color(0xFF82919D),
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
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
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            'NTE LAUNCHER TRADUÇÃO PT-BR  •  COMUNITÁRIO E NÃO OFICIAL',
            style: TextStyle(
              color: Color(0xFFD8E2EA),
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const _CreditsDialog(),
          ),
          icon: const Icon(Icons.favorite_outline_rounded, size: 13),
          label: const Text('CRÉDITOS'),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFFFE58A),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: .9,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'LAUNCHER v${controller.appVersion}',
          style: const TextStyle(
            color: Color(0xFFB7C6D3),
            fontSize: 8,
            fontWeight: FontWeight.w800,
            letterSpacing: .8,
          ),
        ),
      ],
    );
  }
}

class _CreditsDialog extends StatelessWidget {
  const _CreditsDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 470),
        child: _GlassSurface(
          radius: 20,
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _yellow.withValues(alpha: .14),
                      shape: BoxShape.circle,
                      border: Border.all(color: _yellow.withValues(alpha: .42)),
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: _yellow,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FEITO PELA COMUNIDADE',
                          style: TextStyle(
                            color: _yellow,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Créditos do projeto',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Fechar',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Tradução própria gerada pela pipeline NTE Translation '
                'Studio, com revisão e correções da comunidade brasileira.',
                style: TextStyle(color: _muted, fontSize: 10, height: 1.4),
              ),
              const SizedBox(height: 10),
              const _CreditProfile(
                role: 'TRADUÇÃO PT-BR E DESENVOLVIMENTO',
                name: 'MauricioIkeda',
                description:
                    'Responsável pela tradução PT-BR, pipeline automática '
                    'e desenvolvimento do launcher para Windows.',
                githubUrl: 'https://github.com/MauricioIkeda',
                accent: _coral,
                icon: Icons.rocket_launch_rounded,
              ),
              const SizedBox(height: 15),
              const Text(
                'Projeto comunitário, gratuito e sem vínculo oficial com NTE.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF91A4B5), fontSize: 8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditProfile extends StatelessWidget {
  const _CreditProfile({
    required this.role,
    required this.name,
    required this.description,
    required this.githubUrl,
    required this.accent,
    required this.icon,
  });

  final String role;
  final String name;
  final String description;
  final String githubUrl;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openGitHubProfile(context, githubUrl),
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: .3)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role,
                      style: TextStyle(
                        color: accent,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .9,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(color: _muted, fontSize: 9),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Icon(Icons.open_in_new_rounded, color: accent, size: 16),
                  const SizedBox(height: 3),
                  Text(
                    'GITHUB',
                    style: TextStyle(
                      color: accent,
                      fontSize: 7,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .7,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openGitHubProfile(BuildContext context, String url) async {
  final opened = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Não foi possível abrir o GitHub.')),
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
            color: const Color(0xE60A2033),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0x667FD7E8)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x7301060D),
                blurRadius: 34,
                offset: Offset(0, 16),
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
        color: _cyan.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: _cyan.withValues(alpha: .42)),
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

class _TopAction extends StatelessWidget {
  const _TopAction({
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
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: .8,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xA60A2033),
        side: BorderSide(color: Colors.white.withValues(alpha: .3)),
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    LauncherStatus.installing => 'Instalando a tradução no jogo...',
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
    LauncherStatus.completed => _green,
    _ => _cyan,
  };
}
