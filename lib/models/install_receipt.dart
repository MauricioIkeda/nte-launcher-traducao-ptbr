class InstallReceipt {
  const InstallReceipt({
    required this.schemaVersion,
    required this.translationVersion,
    required this.installedAt,
    required this.gameDirectory,
    required this.manifestPublishedAt,
    required this.files,
    this.manifestSha256,
    this.gameBuildId,
    this.sourceHash,
  });

  static const currentSchemaVersion = 2;

  final int schemaVersion;
  final String translationVersion;
  final DateTime installedAt;
  final String gameDirectory;
  final String? manifestSha256;
  final DateTime manifestPublishedAt;
  final String? gameBuildId;
  final String? sourceHash;
  final List<InstalledFileReceipt> files;

  factory InstallReceipt.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != currentSchemaVersion) {
      throw ReceiptFormatException(
        'Schema de recibo não suportado: $schemaVersion.',
      );
    }
    final translationVersion = _requiredString(json, 'translationVersion');
    final gameDirectory = _requiredString(json, 'gameDirectory');
    final installedAt = _requiredDate(json, 'installedAt');
    final manifestPublishedAt = _requiredDate(json, 'manifestPublishedAt');
    final rawFiles = json['files'];
    if (rawFiles is! List || rawFiles.isEmpty) {
      throw const ReceiptFormatException('Recibo sem arquivos.');
    }
    final files = rawFiles
        .map((value) {
          if (value is! Map<String, dynamic>) {
            throw const ReceiptFormatException('Entrada de arquivo inválida.');
          }
          return InstalledFileReceipt.fromJson(value);
        })
        .toList(growable: false);
    final destinations = <String>{};
    for (final file in files) {
      if (!destinations.add(file.relativePath.toLowerCase())) {
        throw const ReceiptFormatException(
          'O recibo contém destinos duplicados.',
        );
      }
    }
    return InstallReceipt(
      schemaVersion: schemaVersion,
      translationVersion: translationVersion,
      installedAt: installedAt,
      gameDirectory: gameDirectory,
      manifestSha256: _optionalHash(json['manifestSha256']),
      manifestPublishedAt: manifestPublishedAt,
      gameBuildId: _optionalString(json['gameBuildId']),
      sourceHash: _optionalHash(json['sourceHash']),
      files: files,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'translationVersion': translationVersion,
    'installedAt': installedAt.toUtc().toIso8601String(),
    'gameDirectory': gameDirectory,
    if (manifestSha256 != null) 'manifestSha256': manifestSha256,
    'manifestPublishedAt': manifestPublishedAt.toUtc().toIso8601String(),
    if (gameBuildId != null) 'gameBuildId': gameBuildId,
    if (sourceHash != null) 'sourceHash': sourceHash,
    'files': files.map((file) => file.toJson()).toList(growable: false),
  };
}

class InstalledFileReceipt {
  const InstalledFileReceipt({
    required this.relativePath,
    required this.installedSize,
    required this.installedSha256,
    required this.originalExisted,
    this.originalSize,
    this.originalSha256,
  });

  final String relativePath;
  final int installedSize;
  final String installedSha256;
  final bool originalExisted;
  final int? originalSize;
  final String? originalSha256;

  factory InstalledFileReceipt.fromJson(Map<String, dynamic> json) {
    final relativePath = _requiredString(json, 'relativePath');
    final installedSize = json['installedSize'];
    final installedSha256 = _requiredHash(json, 'installedSha256');
    final originalExisted = json['originalExisted'];
    if (installedSize is! int ||
        installedSize <= 0 ||
        originalExisted is! bool) {
      throw const ReceiptFormatException(
        'Metadados de arquivo inválidos no recibo.',
      );
    }
    final originalSize = json['originalSize'];
    final originalSha256 = _optionalHash(json['originalSha256']);
    if (originalExisted) {
      if (originalSize is! int || originalSize < 0 || originalSha256 == null) {
        throw const ReceiptFormatException(
          'Metadados do arquivo original estão incompletos.',
        );
      }
    } else if (originalSize != null || originalSha256 != null) {
      throw const ReceiptFormatException(
        'Arquivo sem original contém metadados de backup.',
      );
    }
    return InstalledFileReceipt(
      relativePath: relativePath,
      installedSize: installedSize,
      installedSha256: installedSha256,
      originalExisted: originalExisted,
      originalSize: originalSize as int?,
      originalSha256: originalSha256,
    );
  }

  Map<String, dynamic> toJson() => {
    'relativePath': relativePath,
    'installedSize': installedSize,
    'installedSha256': installedSha256,
    'originalExisted': originalExisted,
    if (originalSize != null) 'originalSize': originalSize,
    if (originalSha256 != null) 'originalSha256': originalSha256,
  };
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw ReceiptFormatException('Campo obrigatório ausente: $key.');
  }
  return value.trim();
}

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw const ReceiptFormatException('Campo de texto opcional inválido.');
  }
  return value.trim();
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  final date = value is String ? DateTime.tryParse(value) : null;
  if (date == null) {
    throw ReceiptFormatException('Data inválida no recibo: $key.');
  }
  return date.toUtc();
}

String _requiredHash(Map<String, dynamic> json, String key) {
  final value = _optionalHash(json[key]);
  if (value == null) {
    throw ReceiptFormatException('Hash obrigatório ausente: $key.');
  }
  return value;
}

String? _optionalHash(Object? value) {
  if (value == null) {
    return null;
  }
  final normalized = value.toString().toLowerCase();
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(normalized)) {
    throw const ReceiptFormatException('Hash inválido no recibo.');
  }
  return normalized;
}

class ReceiptFormatException implements FormatException {
  const ReceiptFormatException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  dynamic get source => null;

  @override
  String toString() => message;
}
