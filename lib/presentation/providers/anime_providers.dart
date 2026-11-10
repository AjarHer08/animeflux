/// Riverpod providers untuk anime browsing, search, detail.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/models/anime.dart';
import '../../data/models/episode.dart';
import '../../data/repositories/anime_repository.dart';

// === Sumber terpilih ===
final selectedSourceProvider = StateProvider<SourceId>(
  (ref) => SourceId.otakudesu,
);

// === Latest anime (sumber terpilih, paginated) ===
class LatestNotifier extends StateNotifier<AsyncValue<List<Anime>>> {
  LatestNotifier(this.ref, this.source)
      : super(const AsyncValue.loading()) {
    _loadFirst();
  }
  final Ref ref;
  final SourceId source;
  int _page = 1;
  bool _hasMore = true;
  List<Anime> _items = [];

  Future<void> _loadFirst() async {
    try {
      _items = await animeRepository.getLatest(source, page: 1);
      _page = 1;
      _hasMore = _items.isNotEmpty;
      state = AsyncValue.data(_items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _loadFirst();
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;
    try {
      final next = await animeRepository.getLatest(source, page: _page + 1);
      if (next.isEmpty) {
        _hasMore = false;
      } else {
        _page += 1;
        _items = [..._items, ...next];
        state = AsyncValue.data(_items);
      }
    } catch (_) {
      // keep current state
    }
  }
}

final latestProvider = StateNotifierProvider.autoDispose
    .family<LatestNotifier, AsyncValue<List<Anime>>, SourceId>(
  (ref, source) => LatestNotifier(ref, source),
);

// === Latest from all sources (paralel) ===
final latestAllProvider = FutureProvider.autoDispose<List<Anime>>((ref) async {
  return animeRepository.getLatestAll(page: 1);
});

// === Detail anime ===
final animeDetailProvider =
    FutureProvider.family<Anime, Anime>((ref, anime) async {
  return animeRepository.getDetail(anime.source, anime);
});

// === Episode detail (mirrors + downloads) ===
final episodeDetailProvider =
    FutureProvider.family<Episode, Episode>((ref, episode) async {
  return animeRepository.getEpisodeDetail(episode.source, episode);
});

// === Search ===
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider =
    FutureProvider.autoDispose<List<Anime>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().length < 2) return const [];
  return animeRepository.searchAll(query);
});

// === Genres ===
final genresProvider =
    FutureProvider.family<List<dynamic>, SourceId>((ref, source) async {
  return animeRepository.getGenres(source);
});
