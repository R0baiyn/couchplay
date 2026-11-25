import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/category_view.dart';
import '../server/models.dart';
import '../server/status_views.dart';
import 'channel.dart';
import 'channel_list_view.dart';
import 'live_player_screen.dart';
import 'live_providers.dart';

/// Onglet TV : catégories de chaînes visibles, puis les chaînes de celle
/// choisie. Même disposition que Films et Séries : catégories en panneau
/// latéral sur grand écran, sinon un bouton dans un en-tête repliable.
class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key, this.headerActions});

  /// Boutons de fin d'en-tête posés par la coquille.
  final Widget? headerActions;

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  static const _title = 'TV';

  String? _selectedId;
  var _refreshing = false;

  /// Dernière chaîne affichée par le lecteur : elle reprend le focus.
  String? _watched;

  void _select(String id) => setState(() => _selectedId = id);

  /// Chaîne choisie (toucher, clic ou OK) : le lecteur, zapping dans la
  /// liste affichée.
  Future<void> _open(Channel channel, List<Channel> channels) async {
    // Remis à zéro : la même chaîne au retour suivant reprend aussi le focus.
    setState(() => _watched = null);
    final last = await openLivePlayer(context, channel, channels);
    if (last != null && mounted) setState(() => _watched = last.id);
  }

  Future<void> _refresh() async {
    // Tirer la liste pendant un rechargement ne le relance pas.
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await ref.read(liveCatalogProvider.notifier).refresh();
      // Le guide (plusieurs Mo) suit sans retenir la liste : ses programmes
      // apparaissent quand il est lu.
      unawaited(ref.read(guideProvider.notifier).refresh());
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _pickCategory(
    List<Category> categories,
    String selectedId,
  ) async {
    final id = await pickCategory(
      context,
      categories: categories,
      selectedId: selectedId,
      tileKey: (id) => ValueKey('live.categorySheetTile.$id'),
    );
    if (id != null && id != selectedId && mounted) _select(id);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(liveCatalogProvider);
    final visible =
        ref.watch(visibleLiveCategoriesProvider).value ?? const <Category>[];
    // Après un changement de compte ou de filtre, l'ancienne sélection peut
    // avoir disparu : la première catégorie visible la remplace.
    final selected =
        visible.where((c) => c.id == _selectedId).firstOrNull ??
        visible.firstOrNull;
    final actions = [
      IconButton(
        key: const ValueKey('live.refresh'),
        tooltip: 'Actualiser',
        icon: const Icon(Icons.refresh),
        onPressed: catalog.isLoading || _refreshing ? null : _refresh,
      ),
      ?widget.headerActions,
    ];

    // Barre fixe, quand il n'y a pas de liste sous laquelle replier l'en-tête
    // (chargement, erreur, grand écran).
    Widget plain(Widget body) => Scaffold(
      appBar: AppBar(
        title: const Text(_title),
        actions: actions,
        bottom: _refreshing ? refreshProgress : null,
      ),
      body: body,
    );

    Widget list(Category category, {Widget? header}) => ChannelList(
      // Une autre catégorie repart en haut.
      key: ValueKey(category.id),
      categoryId: category.id,
      onOpen: _open,
      onRefresh: _refresh,
      focusId: _watched,
      header: header,
    );

    return switch (catalog) {
      AsyncValue(isLoading: true) => plain(
        const Center(child: CircularProgressIndicator()),
      ),
      AsyncError(:final error) => plain(
        ErrorView(
          key: const ValueKey('live.error'),
          error: error,
          onRetry: () => ref.invalidate(liveCatalogProvider),
        ),
      ),
      AsyncData(:final value) when selected == null => plain(
        Column(
          children: [
            if (value.offline)
              OfflineBanner(
                key: const ValueKey('live.offlineBanner'),
                savedAt: value.savedAt,
              ),
            const Expanded(
              child: Center(
                child: Text(
                  key: ValueKey('live.noCategory'),
                  'Aucune catégorie de chaînes à afficher.\n'
                  'Elles se choisissent dans les réglages, sous « Catalogue ».',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
      AsyncData() => LayoutBuilder(
        builder: (context, constraints) {
          final current = selected!;
          // Mêmes seuils que Films et Séries.
          if (constraints.maxWidth >= 1000) {
            return plain(
              Row(
                children: [
                  SizedBox(
                    width: 260,
                    child: CategoryList(
                      categories: visible,
                      selectedId: current.id,
                      onSelect: _select,
                      tileKey: (id) => ValueKey('live.categoryTile.$id'),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: list(current)),
                ],
              ),
            );
          }
          return Scaffold(
            body: list(
              current,
              header: CategoryHeader(
                title: _title,
                actions: actions,
                category: current,
                refreshing: _refreshing,
                pickerKey: const ValueKey('live.categoryPicker'),
                onPick: () => _pickCategory(visible, current.id),
              ),
            ),
          );
        },
      ),
      _ => plain(const SizedBox.shrink()),
    };
  }
}
