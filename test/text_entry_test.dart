import 'package:couchplay/television.dart';
import 'package:couchplay/text_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const dialogField = ValueKey('textEntry.dialogField');
  const ok = ValueKey('textEntry.dialogOk');
  const cancel = ValueKey('textEntry.dialogCancel');
  const toggle = ValueKey('textEntry.dialogToggle');

  late TextEditingController controller;
  late List<String> submitted;

  setUp(() {
    controller = TextEditingController(text: 'départ');
    submitted = [];
  });
  tearDown(() => controller.dispose());

  Future<void> pumpEntry(
    WidgetTester tester, {
    bool television = true,
    bool obscureText = false,
    TextInputAction? action,
    FormFieldValidator<String>? validator,
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [televisionProvider.overrideWithValue(television)],
      child: MaterialApp(
        home: Scaffold(
          body: Form(
            child: Column(
              children: [
                TextEntry(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Adresse'),
                  obscureText: obscureText,
                  textInputAction: action,
                  validator: validator,
                  onSubmitted: submitted.add,
                ),
                const TextField(key: ValueKey('suivant')),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
  }

  testWidgets('hors TV : un champ ordinaire, sans fenêtre de saisie', (
    tester,
  ) async {
    await pumpEntry(tester, television: false);
    expect(find.byType(TextFormField), findsOneWidget);
    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();
    expect(find.byKey(dialogField), findsNothing);
  });

  testWidgets('TV : OK ouvre la fenêtre avec la valeur et le libellé', (
    tester,
  ) async {
    await pumpEntry(tester);
    expect(find.byType(TextFormField), findsNothing);
    await openDialog(tester);

    expect(find.byKey(dialogField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(dialogField)).controller!.text,
      'départ',
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Adresse'),
      ),
      findsOneWidget,
    );
    // Pas un mot de passe : pas de bouton Afficher.
    expect(find.byKey(toggle), findsNothing);
  });

  testWidgets('TV : valider inscrit la valeur et appelle onSubmitted', (
    tester,
  ) async {
    await pumpEntry(tester);
    await openDialog(tester);
    await tester.enterText(find.byKey(dialogField), 'http://exemple.test');
    await tester.tap(find.byKey(ok));
    await tester.pumpAndSettle();

    expect(find.byKey(dialogField), findsNothing);
    expect(controller.text, 'http://exemple.test');
    expect(submitted, ['http://exemple.test']);
  });

  testWidgets('TV : la touche de validation du clavier valide aussi', (
    tester,
  ) async {
    await pumpEntry(tester);
    await openDialog(tester);
    await tester.enterText(find.byKey(dialogField), 'clavier');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(controller.text, 'clavier');
    expect(submitted, ['clavier']);
  });

  testWidgets('TV : annuler ne change rien', (tester) async {
    await pumpEntry(tester);
    await openDialog(tester);
    await tester.enterText(find.byKey(dialogField), 'perdu');
    await tester.tap(find.byKey(cancel));
    await tester.pumpAndSettle();

    expect(find.byKey(dialogField), findsNothing);
    expect(controller.text, 'départ');
    expect(submitted, isEmpty);
  });

  testWidgets(
    'TV : avec « suivant », valider passe le focus au champ suivant',
    (tester) async {
      await pumpEntry(tester, action: TextInputAction.next);
      await openDialog(tester);
      await tester.enterText(find.byKey(dialogField), 'suite');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.text, 'suite');
      expect(submitted, isEmpty);
      final next = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('suivant')),
          matching: find.byType(EditableText),
        ),
      );
      expect(next.focusNode.hasFocus, isTrue);
    },
  );

  testWidgets('TV : mot de passe masqué, Afficher le montre dans la fenêtre', (
    tester,
  ) async {
    controller.text = 'secret';
    await pumpEntry(tester, obscureText: true);
    expect(find.text('••••••'), findsOneWidget);
    expect(find.text('secret'), findsNothing);

    await openDialog(tester);
    bool obscured() =>
        tester.widget<TextField>(find.byKey(dialogField)).obscureText;
    expect(obscured(), isTrue);
    await tester.tap(find.byKey(toggle));
    await tester.pumpAndSettle();
    expect(obscured(), isFalse);
    expect(find.text('Masquer'), findsOneWidget);
  });

  testWidgets('TV : le validateur parle une fois la valeur validée', (
    tester,
  ) async {
    await pumpEntry(
      tester,
      validator: (v) => v == null || v.isEmpty ? 'Obligatoire' : null,
    );
    await openDialog(tester);
    await tester.enterText(find.byKey(dialogField), '');
    await tester.tap(find.byKey(ok));
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);

    Form.of(tester.element(find.byType(FormField<String>))).validate();
    await tester.pump();
    expect(find.text('Obligatoire'), findsOneWidget);
  });
}
