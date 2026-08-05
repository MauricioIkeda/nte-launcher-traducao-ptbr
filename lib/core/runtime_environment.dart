import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _WineGetVersionNative = Pointer<Uint8> Function();
typedef _WineGetVersionDart = Pointer<Uint8> Function();
typedef _WineGetHostVersionNative =
    Void Function(Pointer<Pointer<Uint8>>, Pointer<Pointer<Uint8>>);
typedef _WineGetHostVersionDart =
    void Function(Pointer<Pointer<Uint8>>, Pointer<Pointer<Uint8>>);

class WineRuntimeInfo {
  const WineRuntimeInfo({
    required this.detected,
    this.version,
    this.buildId,
    this.hostSystem,
    this.hostRelease,
  });

  final bool detected;
  final String? version;
  final String? buildId;
  final String? hostSystem;
  final String? hostRelease;

  Map<String, Object?> toJson() => {
    'detected': detected,
    'version': version,
    'buildId': buildId,
    'hostSystem': hostSystem,
    'hostRelease': hostRelease,
  };
}

class RuntimeEnvironment {
  const RuntimeEnvironment._();

  static bool get isWine => detectWine().detected;

  static WineRuntimeInfo detectWine() {
    if (!Platform.isWindows) {
      return const WineRuntimeInfo(detected: false);
    }
    try {
      final library = DynamicLibrary.open('ntdll.dll');
      final versionFunction = library
          .lookupFunction<_WineGetVersionNative, _WineGetVersionDart>(
            'wine_get_version',
          );
      final version = _readNativeString(versionFunction());
      String? buildId;
      try {
        final buildFunction = library
            .lookupFunction<_WineGetVersionNative, _WineGetVersionDart>(
              'wine_get_build_id',
            );
        buildId = _readNativeString(buildFunction());
      } catch (_) {}

      String? hostSystem;
      String? hostRelease;
      final systemPointer = calloc<Pointer<Uint8>>();
      final releasePointer = calloc<Pointer<Uint8>>();
      try {
        final hostFunction = library
            .lookupFunction<_WineGetHostVersionNative, _WineGetHostVersionDart>(
              'wine_get_host_version',
            );
        hostFunction(systemPointer, releasePointer);
        hostSystem = _readNativeString(systemPointer.value);
        hostRelease = _readNativeString(releasePointer.value);
      } catch (_) {
        // Older Wine builds may not expose host version details.
      } finally {
        calloc.free(systemPointer);
        calloc.free(releasePointer);
      }

      return WineRuntimeInfo(
        detected: true,
        version: version,
        buildId: buildId,
        hostSystem: hostSystem,
        hostRelease: hostRelease,
      );
    } catch (_) {
      return const WineRuntimeInfo(detected: false);
    }
  }

  static String? _readNativeString(Pointer<Uint8> pointer) {
    if (pointer == nullptr) return null;
    final bytes = <int>[];
    for (var index = 0; index < 512; index++) {
      final value = pointer[index];
      if (value == 0) break;
      bytes.add(value);
    }
    return bytes.isEmpty ? null : utf8.decode(bytes, allowMalformed: true);
  }
}
