import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Ligne de commande de [startHiddenScript] : le `cmd.exe` de [systemRoot]
/// lance [script] avec [args], chacun entre guillemets (espaces, `&`…).
/// `/s` : cmd retire seulement les guillemets extérieurs. Un guillemet dans
/// un argument casserait la ligne : refusé (jamais dans un chemin Windows).
/// Un `%NOM%` reste développé par cmd s'il nomme une variable existante.
String hiddenCommandLine(String systemRoot, String script, List<String> args) {
  final all = [script, ...args];
  if (all.any((a) => a.contains('"'))) {
    throw ArgumentError('Guillemet dans un argument de script');
  }
  final line = all.map((a) => '"$a"').join(' ');
  return '"$systemRoot\\System32\\cmd.exe" /d /s /c "$line"';
}

/// Lance le script [script] avec [args], dans une console invisible, et
/// n'attend pas sa fin : il survit à l'app.
///
/// Le mode détaché de `dart:io` ne donne aucune console au script : `tasklist`
/// n'y écrit rien et un tube (`|`) y reste bloqué. Le mode normal en ouvre une
/// visible depuis une app graphique.
void startHiddenScript(String script, List<String> args) {
  final commandLine = hiddenCommandLine(
    Platform.environment['SystemRoot'] ?? r'C:\Windows',
    script,
    args,
  );
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
