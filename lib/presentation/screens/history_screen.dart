/// History screen — tampilkan riwayat tonton + resume progress.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/anime.dart';
import '../../data/models/episode.dart';
import '../../data/models/watch_history.dart';
import '../providers/favorites_providers.dart';
import 'player_screen.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(historyListProvider);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Riwayat',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep),
                  tooltip: 'Hapus semua riwayat',
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Hapus semua riwayat?'),
                        content: const Text(
                            'Semua riwayat tonton akan dihapus permanen.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
                          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    final repo = await ref.read(historyRepositoryProvider.future);
                    await repo.clear();
                    ref.invalidate(historyListProvider);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              data: (list) {
                if (list.isEmpty) {
                  return _EmptyState(
                    icon: Icons.history,
                    title: 'Belum ada riwayat',
                    description: 'Setelah menonton, riwayat akan muncul di sini untuk resume cepat.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _HistoryTile(entry: list[i]),
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
}

class _HistoryTile extends StatelessWidget {
  final WatchHistoryEntry entry;
  const _HistoryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: entry.animeCover != null
            ? Image.network(
                entry.animeCover!,
                width: 56,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 56,
                  height: 80,
                  color: scheme.surfaceContainerHighest,
                  child: const Icon(Icons.movie),
                ),
              )
            : Container(
                width: 56,
                height: 80,
                color: scheme.surfaceContainerHighest,
                child: const Icon(Icons.movie),
              ),
      ),
      title: Text(entry.animeTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.episodeTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: entry.progress,
            minHeight: 4,
            backgroundColor: scheme.surfaceContainerHighest,
            color: scheme.primary,
          ),
          const SizedBox(height: 4),
          Text(
            _formatDuration(entry.position) +
                ' / ' +
                _formatDuration(entry.duration),
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
        ],
      ),
      trailing: const Icon(Icons.play_circle_fill),
      onTap: () => _resume(context),
    );
  }

  void _resume(BuildContext context) {
    // Bangun instance Anime minimal dari entry
    final anime = Anime(
      id: entry.animeId,
      source: entry.source,
      title: entry.animeTitle,
      slug: '',
      url: '',
      cover: entry.animeCover,
    );
    final episode = Episode(
      id: entry.episodeId,
      animeId: entry.animeId,
      source: entry.source,
      title: entry.episodeTitle,
      url: entry.episodeUrl,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          anime: anime,
          episode: episode,
          resumeFrom: entry.position,
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
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
