/// Search screen — pencarian anime di semua sumber paralel.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/models/anime.dart';
import '../providers/anime_providers.dart';
import '../widgets/anime_grid.dart';
import 'detail_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  SourceId? _filter;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Cari judul anime...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          ref.read(searchQueryProvider.notifier).state = '';
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
              ),
              onChanged: (v) {
                ref.read(searchQueryProvider.notifier).state = v;
                setState(() {});
              },
              onSubmitted: (v) {
                ref.read(searchQueryProvider.notifier).state = v;
              },
            ),
          ),
          if (_controller.text.length >= 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  children: [
                    FilterChip(
                      label: const Text('Semua'),
                      selected: _filter == null,
                      onSelected: (_) => setState(() => _filter = null),
                    ),
                    ...SourceId.values.map((s) => FilterChip(
                          label: Text(s.label),
                          selected: _filter == s,
                          onSelected: (_) => setState(() => _filter = s),
                        )),
                  ],
                ),
              ),
            ),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final scheme = Theme.of(context).colorScheme;
    if (_controller.text.trim().length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 64, color: scheme.outline),
              const SizedBox(height: 16),
              Text(
                'Cari anime di semua sumber',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Ketik minimal 2 huruf untuk mulai mencari. Hasil dari Otakudesu, Hidoristream, dan Lendrive akan muncul bersamaan.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.outline, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final async = ref.watch(searchResultsProvider);
    return async.when(
      data: (list) {
        final filtered = _filter == null
            ? list
            : list.where((a) => a.source == _filter).toList();
        if (filtered.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off, size: 56, color: scheme.outline),
                  const SizedBox(height: 12),
                  Text('Tidak ada hasil untuk "${_controller.text}"',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          );
        }
        return AnimeGrid(
          animes: filtered,
          onTap: (a) => _goToDetail(context, a),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  void _goToDetail(BuildContext context, Anime anime) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailScreen(anime: anime)),
    );
  }
}
