import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Lance le script [script] avec [args], dans une console invisible, et
/// n'attend pas sa fin : il survit à l'app.
///
/// Le mode détaché de `dart:io` ne donne aucune console au script : `tasklist`
/// n'y écrit rien et un tube (`|`) y reste bloqué. Le mode normal en ouvre une
/// visible depuis une app graphique.
void startHiddenScript(String script, List<String> args) {
  // `/s` : cmd retire seulement les guillemets extérieurs. Un chemin Windows
  // ne contient jamais de guillemet.
  final line = [script, ...args].map((a) => '"$a"').join(' ');
  final commandLine =
      '"${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32\\cmd.exe" '
      '/d /s /c "$line"';
  using((arena) {
    final startup = arena<STARTUPINFO>()..ref.cb = sizeOf<STARTUPINFO>();
    final info = arena<PROCESS_INFORMATION>();
    final result = CreateProcess(
      null,
      PWSTR(commandLine.toNativeUtf16(allocator: arena)),
      null,
      null,
      false,
      CREATE_NO_WINDOW,
      null,
      null,
      startup,
      info,
    );
    if (!result.value) throw OSError('CreateProcess', result.error);
    CloseHandle(info.ref.hProcess);
    CloseHandle(info.ref.hThread);
  });
}
