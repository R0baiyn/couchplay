import 'dart:io';

import 'package:couchplay/update/hidden_process.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart';

void main() {
  test('la ligne ne porte que les variables, chacune entre guillemets', () {
    expect(
      hiddenCommandLine(r'C:\Windows', 2),
      r'"C:\Windows\System32\cmd.exe" /d /e:on /v:off /s /c '
      r'""%COUCHPLAY_ARG0%" "%COUCHPLAY_ARG1%" "%COUCHPLAY_ARG2%""',
    );
  });

  test('chaque mot dans sa variable, script en premier', () {
    expect(
      hiddenArguments(r'C:\Mes jeux\install.cmd', ['42', r'C:\A & B\a.zip']),
      {
        'COUCHPLAY_ARG0': r'C:\Mes jeux\install.cmd',
        'COUCHPLAY_ARG1': '42',
        'COUCHPLAY_ARG2': r'C:\A & B\a.zip',
      },
    );
  });

  test(
    'un %TEMP% littéral arrive intact au script, dans son chemin aussi',
    () async {
      final temp = Directory.systemTemp.createTempSync('couchplay_cmd_');
      addTearDown(() => temp.deleteSync(recursive: true));
      // Un dossier nommé %TEMP% est légal : cmd ne doit pas le développer.
      final dir = Directory('${temp.path}\\%TEMP%')..createSync();
      final script = File('${dir.path}\\s.cmd')
        ..writeAsStringSync('@echo off\r\n>"%~dp0out.txt" echo %~1\r\n');
      const arg = r'C:\%TEMP%\%PATH:~0,3%\100%\app';

      startHiddenScript(script.path, [arg]);

      final out = File('${dir.path}\\out.txt');
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (!out.existsSync() || out.lengthSync() == 0) {
        if (DateTime.now().isAfter(deadline)) fail('Script introuvable');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(out.readAsStringSync().trim(), arg);
      // Les variables ne restent pas dans l'app après le lancement.
      expect(
        using(
          (arena) => GetEnvironmentVariable(
            PCWSTR(hiddenArgument(1).toNativeUtf16(allocator: arena)),
            null,
            0,
          ).value,
        ),
        0,
      );
    },
    skip: !Platform.isWindows,
  );

  test('un guillemet ou un argument vide est refusé', () {
    expect(() => hiddenArguments(r'C:\x.cmd', ['a"b']), throwsArgumentError);
    expect(() => hiddenArguments(r'C:\x.cmd', ['']), throwsArgumentError);
  });
}
