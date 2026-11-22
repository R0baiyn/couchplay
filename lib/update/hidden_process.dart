import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Variable d'environnement qui porte le mot [i] de la ligne de
/// [startHiddenScript] : 0 pour le script, puis ses arguments.
String hiddenArgument(int i) => 'COUCHPLAY_ARG$i';

/// Ligne de commande de [startHiddenScript] : le `cmd.exe` de [systemRoot]
/// lance le script et ses [count] arguments, chacun lu dans sa variable
/// ([hiddenArgument]) et entre guillemets (espaces, `&`…). Les chemins ne
/// sont jamais dans la ligne : cmd y développe `%NOM%` une seule fois, donc
/// un `%` d'un chemin (dossier `%TEMP%`, `100%`) arrive tel quel au script.
/// `/s` : cmd retire seulement les guillemets extérieurs. `/v:off` : un `!`
/// n'est jamais développé.
String hiddenCommandLine(String systemRoot, int count) {
  final line = [for (var i = 0; i <= count; i++) '"%${hiddenArgument(i)}%"']
      .join(' ');
  return '"$systemRoot\\System32\\cmd.exe" /d /v:off /s /c "$line"';
}

/// Valeurs des variables de [hiddenCommandLine] pour [script] et [args]. Un
/// guillemet casserait la ligne (jamais dans un chemin Windows), une valeur
/// vide laisserait `%NOM%` tel quel : refusés.
Map<String, String> hiddenArguments(String script, List<String> args) {
  final all = [script, ...args];
  if (all.any((a) => a.isEmpty || a.contains('"'))) {
    throw ArgumentError('Argument de script vide ou avec un guillemet');
  }
  return {for (final (i, a) in all.indexed) hiddenArgument(i): a};
}

/// Lance le script [script] avec [args], dans une console invisible, et
/// n'attend pas sa fin : il survit à l'app. Les arguments passent par des
/// variables d'environnement de l'app, héritées par le script.
///
/// Le mode détaché de `dart:io` ne donne aucune console au script : `tasklist`
/// n'y écrit rien et un tube (`|`) y reste bloqué. Le mode normal en ouvre une
/// visible depuis une app graphique.
void startHiddenScript(String script, List<String> args) {
  final variables = hiddenArguments(script, args);
  final commandLine = hiddenCommandLine(
    Platform.environment['SystemRoot'] ?? r'C:\Windows',
    args.length,
  );
  using((arena) {
    for (final MapEntry(:key, :value) in variables.entries) {
      final set = SetEnvironmentVariable(
        PCWSTR(key.toNativeUtf16(allocator: arena)),
        PCWSTR(value.toNativeUtf16(allocator: arena)),
      );
      if (!set.value) throw OSError('SetEnvironmentVariable', set.error);
    }
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
