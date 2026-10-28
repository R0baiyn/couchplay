import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'television.dart';

/// Champ de texte adapté à l'appareil.
///
/// Sur téléphone et ordinateur, un [TextFormField] ordinaire. Sur TV, une
/// case qui en a l'allure mais qu'on traverse aux flèches sans ouvrir le
/// clavier à l'écran : OK ouvre une fenêtre de saisie ; validée, la valeur
/// s'inscrit et le focus passe au champ suivant ([TextInputAction.next]),
/// ou [onSubmitted] est appelé.
class TextEntry extends ConsumerWidget {
  const TextEntry({
    super.key,
    required this.controller,
    this.decoration = const InputDecoration(),
    this.focusNode,
    this.autofocus = false,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.validator,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autocorrect;
  final bool enableSuggestions;
  final FormFieldValidator<String>? validator;

  /// À chaque frappe (téléphone, ordinateur seulement).
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(televisionProvider)) return _TvEntry(field: this);
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      decoration: decoration,
    );
  }
}

class _TvEntry extends StatefulWidget {
  const _TvEntry({required this.field});

  final TextEntry field;

  @override
  State<_TvEntry> createState() => _TvEntryState();
}

class _TvEntryState extends State<_TvEntry> {
  var _focused = false;

  TextEntry get _field => widget.field;

  Future<void> _edit(FormFieldState<String> state) async {
    final decoration = _field.decoration;
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _EntryDialog(
        title: decoration.labelText ?? decoration.hintText ?? '',
        initial: _field.controller.text,
        obscureText: _field.obscureText,
        keyboardType: _field.keyboardType,
        autocorrect: _field.autocorrect,
        enableSuggestions: _field.enableSuggestions,
      ),
    );
    if (value == null || !mounted) return;
    _field.controller.text = value;
    state.didChange(value);
    if (_field.textInputAction == TextInputAction.next) {
      FocusScope.of(context).nextFocus();
    } else {
      _field.onSubmitted?.call(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _field.controller;
    return FormField<String>(
      initialValue: controller.text,
      validator: _field.validator == null
          ? null
          : (_) => _field.validator!(controller.text),
      builder: (state) => InkWell(
        focusNode: _field.focusNode,
        autofocus: _field.autofocus,
        borderRadius: BorderRadius.circular(4),
        onFocusChange: (focused) => setState(() => _focused = focused),
        onTap: () => _edit(state),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final text = controller.text;
            return InputDecorator(
              decoration: _field.decoration.copyWith(
                errorText: state.errorText,
                suffixIcon:
                    _field.decoration.suffixIcon ?? const Icon(Icons.edit),
              ),
              isFocused: _focused,
              isEmpty: text.isEmpty,
              child: Text(
                // Masqué, sans en dire la longueur exacte au-delà de 8.
                _field.obscureText ? '•' * text.length.clamp(0, 8) : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Saisie d'une valeur : le clavier à l'écran s'ouvre ; « OK », ou la touche
/// de validation du clavier, rend le texte, « Annuler » ou retour rend `null`.
class _EntryDialog extends StatefulWidget {
  const _EntryDialog({
    required this.title,
    required this.initial,
    required this.obscureText,
    required this.keyboardType,
    required this.autocorrect,
    required this.enableSuggestions,
  });

  final String title;
  final String initial;
  final bool obscureText;
  final TextInputType? keyboardType;
  final bool autocorrect;
  final bool enableSuggestions;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        autocorrect: widget.autocorrect,
        enableSuggestions: widget.enableSuggestions,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
