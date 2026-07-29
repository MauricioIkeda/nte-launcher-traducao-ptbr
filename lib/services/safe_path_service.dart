import 'dart:io';

import 'package:path/path.dart' as p;

class SafePathService {
  Future<String> canonicalDirectory(String value) async {
    if (value.trim().isEmpty) {
      throw const UnsafePathException('O diretório está vazio.');
    }
    var normalized = p.normalize(p.absolute(value.trim()));
    final directory = Directory(normalized);
    if (await directory.exists()) {
      try {
        normalized = p.normalize(await directory.resolveSymbolicLinks());
      } on FileSystemException {
        // The lexical absolute path is still useful for an access error result.
      }
    }
    return _platformNormalize(normalized);
  }

  String normalizeRelative(String value) {
    final portable = value.replaceAll('\\', '/');
    if (portable.isEmpty ||
        portable.startsWith('/') ||
        portable.startsWith('//') ||
        RegExp(r'^[A-Za-z]:').hasMatch(portable) ||
        p.isAbsolute(value)) {
      throw UnsafePathException('Caminho absoluto não permitido: $value.');
    }
    final segments = portable.split('/');
    if (segments.any(
      (segment) =>
          segment.isEmpty ||
          segment == '.' ||
          segment == '..' ||
          segment.contains(':'),
    )) {
      throw UnsafePathException('Caminho relativo inseguro: $value.');
    }
    return p.joinAll(segments);
  }

  Future<File> resolveFile(String root, String relative) async {
    final normalizedRelative = normalizeRelative(relative);
    final canonicalRoot = await canonicalDirectory(root);
    final candidate = p.normalize(p.join(canonicalRoot, normalizedRelative));
    if (!_isWithinOrEqual(canonicalRoot, candidate) ||
        _samePath(canonicalRoot, candidate)) {
      throw UnsafePathException(
        'Destino fora do diretório permitido: $relative.',
      );
    }
    await _rejectUnsafeAncestors(canonicalRoot, candidate);
    final candidateType = await FileSystemEntity.type(
      candidate,
      followLinks: false,
    );
    if (candidateType == FileSystemEntityType.link) {
      throw UnsafePathException(
        'O arquivo de destino é um link simbólico: $relative.',
      );
    }
    return File(candidate);
  }

  Future<void> _rejectUnsafeAncestors(String root, String candidate) async {
    var current = p.dirname(candidate);
    while (_isWithinOrEqual(root, current) && !_samePath(root, current)) {
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw UnsafePathException('Link simbólico não permitido: $current.');
      }
      if (type == FileSystemEntityType.directory) {
        try {
          final resolved = _platformNormalize(
            p.normalize(await Directory(current).resolveSymbolicLinks()),
          );
          if (!_isWithinOrEqual(root, resolved)) {
            throw UnsafePathException(
              'Junction ou reparse point sai do diretório do jogo: $current.',
            );
          }
        } on UnsafePathException {
          rethrow;
        } on FileSystemException {
          // Access errors are classified later by the integrity operation.
        }
      }
      current = p.dirname(current);
    }
  }

  bool sameDirectory(String first, String second) {
    return _samePath(
      _platformNormalize(p.normalize(p.absolute(first.trim()))),
      _platformNormalize(p.normalize(p.absolute(second.trim()))),
    );
  }

  bool _isWithinOrEqual(String root, String value) {
    final normalizedRoot = _platformNormalize(root);
    final normalizedValue = _platformNormalize(value);
    return normalizedValue == normalizedRoot ||
        p.isWithin(normalizedRoot, normalizedValue);
  }

  bool _samePath(String first, String second) =>
      _platformNormalize(first) == _platformNormalize(second);

  String _platformNormalize(String value) {
    var normalized = p.normalize(value);
    while (normalized.length > p.rootPrefix(normalized).length &&
        (normalized.endsWith('/') || normalized.endsWith('\\'))) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}

class UnsafePathException implements Exception {
  const UnsafePathException(this.message);

  final String message;

  @override
  String toString() => message;
}
