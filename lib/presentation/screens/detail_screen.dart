/// Detail screen — info anime, episode list, tombol play.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/anime.dart';
import '../../data/models/episode.dart';
import '../providers/anime_providers.dart';
import '../providers/favorites_providers.dart';
import '../widgets/episode_download_sheet.dart';
import 'player_screen.dart';

class DetailScreen extends ConsumerWidget {
  final Anime anime;
  const DetailScreen({super.key, required this.anime});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(animeDetailProvider(anime));
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  (anime.cover != null || anime.banner != null)
                      ? CachedNetworkImage(
                          imageUrl: anime.banner ?? anime.cover ?? '',
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: scheme.surfaceContainerHighest,
                          ),
                        )
                      : Container(color: scheme.surfaceContainerHighest),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          scheme.surface.withOpacity(0.7),
                          scheme.surface.withOpacity(1),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    bottom: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          anime.title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (anime.altTitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              anime.altTitle!,
                              style: TextStyle(
                                color: scheme.outline,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              Consumer(builder: (context, ref, _) {
                final isFav = ref.watch(favoriteStatusProvider(anime.id));
                return IconButton(
                  icon: Icon(
                    isFav ? Icons.bookmark : Icons.bookmark_outline,
                    color: isFav ? scheme.primary : null,
                  ),
                  tooltip: 'Favorit',
                  onPressed: () {
                    ref
                        .read(favoriteStatusProvider(anime.id).notifier)
                        .toggle(anime);
                  },
                );
              }),
            ],
          ),
          SliverToBoxAdapter(
            child: detail.when(
              data: (a) => _DetailBody(anime: a),
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Gagal memuat detail: $e',
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  final Anime anime;
  const _DetailBody({required this.anime});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick info chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (anime.status != null)
                _InfoChip(label: 'Status', value: anime.status!, color: scheme.primaryContainer),
              if (anime.type != null)
                _InfoChip(label: 'Tipe', value: anime.type!),
              if (anime.totalEpisodes != null)
                _InfoChip(label: 'Total EP', value: '${anime.totalEpisodes}'),
              if (anime.score != null)
                _InfoChip(
                  label: 'Skor',
                  value: anime.score!.toStringAsFixed(1),
                  icon: Icons.star,
                  color: scheme.tertiaryContainer,
                ),
              if (anime.studio != null) _InfoChip(label: 'Studio', value: anime.studio!),
              if (anime.releaseDate != null)
                _InfoChip(label: 'Rilis', value: anime.releaseDate!),
            ],
          ),
          if (anime.genres.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: anime.genres.map((g) {
                return ActionChip(
                  label: Text(g.name),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Filter genre ${g.name} belum implementasi')),
                    );
                  },
                );
              }).toList(),
            ),
          ],
          if (anime.synopsis != null) ...[
            const SizedBox(height: 16),
            Text('Sinopsis',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Html(data: anime.synopsis!),
          ],
          const SizedBox(height: 16),
          Text('Episode (${anime.episodes.length})',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (anime.episodes.isEmpty)
            Text('Belum ada episode.', style: TextStyle(color: scheme.outline))
          else
            ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: anime.episodes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final ep = anime.episodes[i];
                return _EpisodeRow(anime: anime, episode: ep);
              },
            ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final IconData? icon;
  const _InfoChip({required this.label, required this.value, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = color ?? scheme.surfaceContainerHighest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: scheme.primary),
            const SizedBox(width: 4),
          ],
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  final Anime anime;
  final Episode episode;
  const _EpisodeRow({required this.anime, required this.episode});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        child: Text(episode.number ?? '?'),
      ),
      title: Text(episode.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Download',
            onPressed: () => showEpisodeDownloadSheet(context, anime, episode),
          ),
          const Icon(Icons.play_arrow_rounded),
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlayerScreen(anime: anime, episode: episode),
          ),
        );
      },
    );
  }
}
