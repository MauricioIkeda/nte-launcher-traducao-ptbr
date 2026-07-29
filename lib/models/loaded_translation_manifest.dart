import 'translation_manifest.dart';

enum ManifestSource { remote, cache, bundled }

class LoadedTranslationManifest {
  const LoadedTranslationManifest({
    required this.manifest,
    required this.source,
  });

  final TranslationManifest manifest;
  final ManifestSource source;

  bool get isAuthoritative => source == ManifestSource.remote;
  bool get isOffline => source != ManifestSource.remote;
}
