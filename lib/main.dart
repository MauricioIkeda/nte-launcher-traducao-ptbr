import 'package:flutter/material.dart';

import 'core/app_paths.dart';
import 'core/launcher_log.dart';
import 'core/trusted_http_client.dart';
import 'launcher_controller.dart';
import 'services/download_service.dart';
import 'services/elevation_service.dart';
import 'services/installation_service.dart';
import 'services/manifest_repository.dart';
import 'services/settings_service.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await TrustedHttpClientFactory.initialize();
  final paths = await AppPaths.create();
  final log = LauncherLog(paths.logFile);
  final controller = LauncherController(
    paths: paths,
    log: log,
    manifests: ManifestRepository(paths, log),
    downloads: DownloadService(paths, log),
    elevation: ElevationService(log),
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF25D4F2),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF080C17),
        cardTheme: const CardThemeData(
          color: Color(0xFF111827),
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF0B1220),
          border: OutlineInputBorder(),
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
        final controller = widget.controller;
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF07101F), Color(0xFF11132A)],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Header(),
                        const SizedBox(height: 28),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 3,
                                child: _MainCard(controller: controller),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                flex: 2,
                                child: _SecurityCard(controller: controller),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFF25D4F2),
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Icon(Icons.translate, color: Color(0xFF03131A), size: 32),
          ),
        ),
        SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NTE TRADUÇÃO PT-BR',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              'Instalação segura, verificável e reversível',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      ],
    );
  }
}

class _MainCard extends StatelessWidget {
  const _MainCard({required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    final manifest = controller.manifest;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'Tradução',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                _VersionChip(
                  label: manifest == null
                      ? 'Carregando'
                      : 'v${manifest.translationVersion}',
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Pasta do jogo',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: controller.isBusy ? null : controller.chooseGameDirectory,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1220),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF263247)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open, color: Color(0xFF25D4F2)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        controller.gameDirectory ?? 'Selecionar pasta...',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            _StatusArea(controller: controller),
            const Spacer(),
            if (controller.errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A111A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  controller.errorMessage!,
                  style: const TextStyle(color: Color(0xFFFFA3B1)),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                if (controller.status == LauncherStatus.downloading)
                  OutlinedButton.icon(
                    onPressed: controller.cancelDownload,
                    icon: const Icon(Icons.close),
                    label: const Text('Cancelar'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: controller.isInstalled && !controller.isBusy
                        ? controller.removeTranslation
                        : null,
                    icon: const Icon(Icons.restore),
                    label: const Text('Restaurar original'),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: controller.canInstall
                      ? controller.installOrUpdate
                      : null,
                  icon: const Icon(Icons.download_done),
                  label: Text(
                    controller.isInstalled ? 'Atualizar' : 'Instalar tradução',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusArea extends StatelessWidget {
  const _StatusArea({required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    final statusText = switch (controller.status) {
      LauncherStatus.starting => 'Preparando launcher...',
      LauncherStatus.ready =>
        controller.isInstalled
            ? 'Tradução instalada: v${controller.installedVersion}'
            : 'Pronto para instalar',
      LauncherStatus.downloading => 'Baixando ${controller.currentFile}',
      LauncherStatus.installing => 'Instalando com proteção de rollback...',
      LauncherStatus.completed => 'Tradução instalada com sucesso',
      LauncherStatus.removing => 'Restaurando arquivos originais...',
      LauncherStatus.error => 'Operação interrompida',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              controller.status == LauncherStatus.error
                  ? Icons.error_outline
                  : Icons.verified_outlined,
              color: controller.status == LauncherStatus.error
                  ? const Color(0xFFFF6B81)
                  : const Color(0xFF4ADE80),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(statusText)),
            if (controller.totalBytes > 0)
              Text('${(controller.progress * 100).toStringAsFixed(0)}%'),
          ],
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: controller.status == LauncherStatus.starting
              ? null
              : controller.progress,
          minHeight: 8,
          borderRadius: BorderRadius.circular(99),
        ),
      ],
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Proteções ativas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            const _Protection(
              icon: Icons.api_outlined,
              title: 'Sem API limitada',
              subtitle: 'Manifesto estático e cache local',
            ),
            const _Protection(
              icon: Icons.lock_outline,
              title: 'TLS confiável',
              subtitle: 'Bundle oficial Mozilla/cURL',
            ),
            const _Protection(
              icon: Icons.fingerprint,
              title: 'SHA-256',
              subtitle: 'Todos os arquivos são verificados',
            ),
            const _Protection(
              icon: Icons.restart_alt,
              title: 'Download retomável',
              subtitle: 'Continua de onde parou',
            ),
            const _Protection(
              icon: Icons.settings_backup_restore,
              title: 'Backup e rollback',
              subtitle: 'Restaura os arquivos originais',
            ),
            const Spacer(),
            Text(
              'Log técnico:\n${controller.paths.logFile.path}',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: controller.gameDirectory != null && !controller.isBusy
                  ? controller.launchGame
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Abrir jogo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Protection extends StatelessWidget {
  const _Protection({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF25D4F2), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF12303A),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF67E8F9),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
