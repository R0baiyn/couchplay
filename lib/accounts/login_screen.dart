import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../server/server_client.dart';
import 'account.dart';
import 'account_store.dart';
import 'server_session.dart';

/// Ajout d'un compte, ou modification de [account] (même `id`, donc mêmes
/// données). Le compte n'est enregistré qu'une fois la connexion réussie.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.account});

  final Account? account;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.account?.name);
  late final _host = TextEditingController(text: widget.account?.host);
  late final _username = TextEditingController(text: widget.account?.username);
  // Jamais prérempli : n'importe qui avec la télécommande pourrait le lire.
  final _password = TextEditingController();
  late final _userAgent = TextEditingController(
    text: widget.account?.userAgent ?? defaultUserAgent,
  );
  var _busy = false;
  var _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _host, _username, _password, _userAgent]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final host = normalizeHost(_host.text);
    final account = Account(
      id: widget.account?.id ?? Account.newId(),
      name: _name.text.trim().isEmpty ? host : _name.text.trim(),
      host: host,
      username: _username.text.trim(),
      // Vide en modification : le mot de passe enregistré est conservé.
      password: _password.text.isEmpty && widget.account != null
          ? widget.account!.password
          : _password.text,
      userAgent: _userAgent.text.trim().isEmpty
          ? defaultUserAgent
          : _userAgent.text.trim(),
    );

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(serverClientFactoryProvider)(account).accountInfo();
      // Un nouveau compte devient actif ; une modification ne change pas l'actif.
      await ref
          .read(accountsProvider.notifier)
          .save(account, activate: widget.account == null);
    } on ServerException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    } on Exception {
      // Stockage sécurisé indisponible : rien n'est enregistré.
      if (mounted) {
        setState(() => _error = 'Impossible d\'enregistrer le compte');
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
  }

  String? _required(String? value) =>
      (value ?? '').trim().isEmpty ? 'Champ requis' : null;

  @override
  Widget build(BuildContext context) {
    final editing = widget.account != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Modifier le compte' : 'Ajouter un compte'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  TextFormField(
                    controller: _name,
                    autofocus: !editing,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nom du compte',
                      hintText: 'Par exemple « Salon »',
                    ),
                  ),
                  TextFormField(
                    controller: _host,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    validator: (value) => hostError(value ?? ''),
                    decoration: const InputDecoration(
                      labelText: 'Adresse du serveur',
                      hintText: 'http://serveur.com:8080',
                    ),
                  ),
                  TextFormField(
                    controller: _username,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    // Ni saisie automatique ni suggestions : les identifiants
                    // ne vivent que dans le stockage sécurisé de l'app.
                    enableSuggestions: false,
                    validator: _required,
                    decoration: const InputDecoration(labelText: 'Utilisateur'),
                  ),
                  TextFormField(
                    controller: _password,
                    obscureText: _hidePassword,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    validator: (value) => (value ?? '').isEmpty && !editing
                        ? 'Champ requis'
                        : null,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      helperText: editing
                          ? 'Laisser vide pour garder le mot de passe actuel'
                          : null,
                      suffixIcon: IconButton(
                        tooltip: _hidePassword
                            ? 'Afficher le mot de passe'
                            : 'Masquer le mot de passe',
                        icon: Icon(
                          _hidePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () =>
                            setState(() => _hidePassword = !_hidePassword),
                      ),
                    ),
                  ),
                  TextFormField(
                    controller: _userAgent,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'User-Agent',
                      helperText: 'À changer seulement si le serveur refuse',
                    ),
                  ),
                  if (_error case final error?)
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(editing ? 'Enregistrer' : 'Se connecter'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
