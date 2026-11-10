/// Provider untuk favorites & history.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/anime.dart';
import '../../data/models/watch_history.dart';
import '../../data/repositories/favorites_repository.dart';
import '../../data/repositories/history_repository.dart';
import 'shared_prefs_provider.dart';

// === Favorites ===
final favoritesRepositoryProvider = FutureProvider<FavoritesRepository>(
  (ref) async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    return FavoritesRepository(prefs);
  },
);

final favoritesListProvider =
    FutureProvider<List<Anime>>((ref) async {
  final repo = await ref.watch(favoritesRepositoryProvider.future);
  return repo.getAll();
});

class FavoriteStatusNotifier extends StateNotifier<bool> {
  FavoriteStatusNotifier(this.repo, this.animeId) : super(false) {
    state = repo.isFavorite(animeId);
  }
  final FavoritesRepository repo;
  final String animeId;

  Future<void> toggle(Anime anime) async {
    await repo.toggle(anime);
    state = repo.isFavorite(animeId);
  }
}

final favoriteStatusProvider = StateNotifierProvider.autoDispose
    .family<FavoriteStatusNotifier, bool, String>((ref, animeId) {
  final repoAsync = ref.watch(favoritesRepositoryProvider);
  return repoAsync.when(
    data: (repo) => FavoriteStatusNotifier(repo, animeId),
    loading: () => FavoriteStatusNotifier(_NullFavorites(), animeId),
    error: (e, st) => FavoriteStatusNotifier(_NullFavorites(), animeId),
  );
});

class _NullFavorites implements FavoritesRepository {
  @override
  noSuchMethod(Invocation invocation) {}
}

// === History ===
final historyRepositoryProvider = FutureProvider<HistoryRepository>(
  (ref) async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    return HistoryRepository(prefs);
  },
);

final historyListProvider = FutureProvider<List<WatchHistoryEntry>>((ref) async {
  final repo = await ref.watch(historyRepositoryProvider.future);
  return repo.getAll();
});
