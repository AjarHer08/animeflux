/// Favorites screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/anime.dart';
import '../providers/favorites_providers.dart';
import '../widgets/anime_grid.dart';
import 'detail_screen.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(favoritesListProvider);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Favorit',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: async.when(
              data: (list) {
                if (list.isEmpty) {
                  return _EmptyState(
                    icon: Icons.bookmark_outline,
                    title: 'Belum ada favorit',
                    description: 'Tekan ikon bookmark di halaman detail anime untuk menyimpan ke favorit.',
                  );
                }
                return AnimeGrid(
                  animes: list,
                  onTap: (a) => _goToDetail(context, ref, a),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  void _goToDetail(BuildContext context, WidgetRef ref, Anime anime) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailScreen(anime: anime)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: scheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
