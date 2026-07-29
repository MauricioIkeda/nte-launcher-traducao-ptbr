class TranslationManifest {
  const TranslationManifest({
    required this.schemaVersion,
    required this.translationVersion,
    required this.publishedAt,
    required this.files,
    this.gameBuildId,
    this.sourceHash,
  });

  final int schemaVersion;
  final String translationVersion;
  final DateTime publishedAt;
  final List<TranslationFile> files;
  final String? gameBuildId;
  final String? sourceHash;

  int get totalBytes => files.fold(0, (total, file) => total + file.size);

  factory TranslationManifest.fromJson(Map<String, dynamic> json) {
    final manifest = TranslationManifest(
      schemaVersion: json['schemaVersion'] as int,
      translationVersion: json['translationVersion'] as String,
      publishedAt: DateTime.parse(json['publishedAt'] as String).toUtc(),
      gameBuildId: _optionalNonEmptyString(json['gameBuildId']),
      sourceHash: _optionalSha256(json['sourceHash']),
      files: (json['files'] as List<dynamic>)
          .map(
            (value) => TranslationFile.fromJson(value as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
    manifest.validate();
    return manifest;
  }

  void validate() {
    if (schemaVersion != 1) {
      throw const FormatException('Versão de manifesto não suportada.');
    }
    if (translationVersion.trim().isEmpty || files.isEmpty) {
      throw const FormatException('Manifesto incompleto.');
    }
    final names = <String>{};
    final destinations = <String>{};
    for (final file in files) {
      file.validate();
      if (!names.add(file.name) ||
          !destinations.add(file.relativeDestination.toLowerCase())) {
        throw const FormatException('Arquivo duplicado no manifesto.');
      }
    }
  }

  static String? _optionalNonEmptyString(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Identificador de build inválido.');
    }
    return value.trim();
  }

  static String? _optionalSha256(Object? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.toString().toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(normalized)) {
      throw const FormatException('Hash de fonte inválido.');
    }
    return normalized;
  }
}

class TranslationFile {
  const TranslationFile({
    required this.name,
    required this.relativeDestination,
    required this.url,
    required this.size,
    required this.sha256,
  });

  final String name;
  final String relativeDestination;
  final Uri url;
  final int size;
  final String sha256;

  factory TranslationFile.fromJson(Map<String, dynamic> json) {
    return TranslationFile(
      name: json['name'] as String,
      relativeDestination: json['relativeDestination'] as String,
      url: Uri.parse(json['url'] as String),
      size: json['size'] as int,
      sha256: (json['sha256'] as String).toLowerCase(),
    );
  }

  void validate() {
    final pathSegments = relativeDestination.replaceAll('\\', '/').split('/');
    if (name.trim().isEmpty ||
        pathSegments.isEmpty ||
        pathSegments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        ) ||
        relativeDestination.startsWith('/') ||
        relativeDestination.contains(':')) {
      throw FormatException('Destino inválido para $name.');
    }
    if (url.scheme != 'https' || url.host.isEmpty) {
      throw FormatException('URL insegura para $name.');
    }
    if (size <= 0 || !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw FormatException('Metadados de integridade inválidos para $name.');
    }
  }
}
