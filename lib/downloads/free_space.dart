import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Place libre pour l'utilisateur dans le volume de [directory], en
/// octets ; `null` si on ne sait pas la lire (la place manquante se verra
/// alors à l'écriture). Windows : `GetDiskFreeSpaceExW` ; Android et Linux
/// 64 bits : `statvfs`.
///
/// `ponytail:` rien sur Android 32 bits (armv7) : la disposition de
/// `struct statvfs` y diffère et n'a pas pu être vérifiée ; le disque plein
/// y est vu à l'écriture.
Future<int?> freeSpace(Directory directory) async {
  try {
    if (Platform.isWindows) return _windows(directory.path);
    if ((Platform.isAndroid || Platform.isLinux) && sizeOf<IntPtr>() == 8) {
      return _statvfs(directory.path);
    }
  } on Object {
    // Bibliothèque ou fonction introuvable : place inconnue.
  }
  return null;
}

int? _windows(String path) => using((arena) {
  final free = arena<Uint64>();
  final result = GetDiskFreeSpaceEx(
    PCWSTR(path.toNativeUtf16(allocator: arena)),
    free,
    null,
    null,
  );
  return result.value ? free.value : null;
});

typedef _StatvfsNative = Int32 Function(Pointer<Utf8>, Pointer<Uint64>);
typedef _Statvfs = int Function(Pointer<Utf8>, Pointer<Uint64>);

/// `struct statvfs` en 64 bits (glibc et bionic) : `f_bsize`, `f_frsize`,
/// `f_blocks`, `f_bfree`, `f_bavail`… sur 8 octets chacun, 112 octets en
/// tout.
int? _statvfs(String path) => using((arena) {
  final statvfs = DynamicLibrary.open(
    Platform.isAndroid ? 'libc.so' : 'libc.so.6',
  ).lookupFunction<_StatvfsNative, _Statvfs>('statvfs');
  final fields = arena<Uint64>(32);
  if (statvfs(path.toNativeUtf8(allocator: arena), fields) != 0) return null;
  return fields[1] * fields[4];
});
