import 'package:couchplay/update/hidden_process.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const root = r'C:\Windows';

  test('chaque argument entre guillemets, espaces et & compris', () {
    expect(
      hiddenCommandLine(root, r'C:\Mes jeux\install.cmd', [
        '42',
        r'C:\A & B\app.zip',
      ]),
      r'"C:\Windows\System32\cmd.exe" /d /s /c '
      r'""C:\Mes jeux\install.cmd" "42" "C:\A & B\app.zip""',
    );
  });

  test('un % est passé tel quel (cmd le développera)', () {
    expect(
      hiddenCommandLine(root, r'C:\x.cmd', [r'C:\100%\app']),
      endsWith(r'"C:\100%\app""'),
    );
  });

  test('un guillemet dans un argument est refusé', () {
    expect(
      () => hiddenCommandLine(root, r'C:\x.cmd', ['a"b']),
      throwsArgumentError,
    );
  });
}
