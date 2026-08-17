class AppUpdateManifest {
  const AppUpdateManifest({
    required this.schemaVersion,
    required this.version,
    required this.publishedAt,
    required this.installerUrl,
    required this.installerSize,
    required this.installerSha256,
    required this.releaseNotes,
    required this.mandatory,
  });

  final int schemaVersion;
  final String version;
  final DateTime publishedAt;
  final Uri installerUrl;
  final int installerSize;
  final String installerSha256;
  final String releaseNotes;
  final bool mandatory;

  factory AppUpdateManifest.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException(
        'Versão de esquema do launcher não suportada.',
      );
    }
    final version = json['version'];
    final publishedAt = DateTime.tryParse(
      json['publishedAt']?.toString() ?? '',
    );
    final installer = json['installer'];
    if (version is! String ||
        !_semanticVersion.hasMatch(version) ||
        publishedAt == null ||
        installer is! Map<String, dynamic>) {
      throw const FormatException('Manifesto de atualização inválido.');
    }

    final url = Uri.tryParse(installer['url']?.toString() ?? '');
    final size = installer['size'];
    final sha256 = installer['sha256']?.toString().toLowerCase() ?? '';
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'github.com' ||
        size is! int ||
        size <= 0 ||
        !_sha256.hasMatch(sha256)) {
      throw const FormatException('Instalador de atualização inválido.');
    }

    return AppUpdateManifest(
      schemaVersion: 1,
      version: version,
      publishedAt: publishedAt.toUtc(),
      installerUrl: url,
      installerSize: size,
      installerSha256: sha256,
      releaseNotes: json['releaseNotes']?.toString().trim() ?? '',
      mandatory: json['mandatory'] == true,
    );
  }

  bool isNewerThan(String currentVersion) {
    final available = _parts(version);
    final current = _parts(currentVersion);
    for (var index = 0; index < 3; index++) {
      if (available[index] != current[index]) {
        return available[index] > current[index];
      }
    }
    return false;
  }

  bool shouldInstallAutomatically(bool userPreference) =>
      mandatory || userPreference;

  static List<int> _parts(String value) {
    final match = _semanticVersion.firstMatch(value);
    if (match == null) {
      throw FormatException('Versão semântica inválida: $value');
    }
    return [
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
  }

  static final _semanticVersion = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');
  static final _sha256 = RegExp(r'^[a-f0-9]{64}$');
}
