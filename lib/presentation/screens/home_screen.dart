/// Home screen — section rilisan terbaru per sumber, ongoing, dan trending.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/models/anime.dart';
import '../../data/repositories/anime_repository.dart';
import '../providers/anime_providers.dart';
import '../widgets/anime_grid.dart';
import '../widgets/section_header.dart';
import '../widgets/source_selector.dart';
import 'detail_screen.dart';
import 'ongoing_screen.dart';
import 'schedule_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  SourceId _source = SourceId.otakudesu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AnimeFlux',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Streaming & download anime dari 3 sumber',
                          style: TextStyle(color: scheme.outline, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.calendar_month_outlined),
                    tooltip: 'Jadwal Rilis',
                    onPressed: () => _navigateSchedule(context),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SourceSelector(
                value: _source,
                onChanged: (s) => setState(() => _source = s),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Ongoing'),
                      onPressed: () => _openList(context, completed: false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Completed'),
                      onPressed: () => _openList(context, completed: true),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: _LatestSection(source: _source)),
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'Ongoing',
              subtitle: 'Sedang tayang dari sumber terpilih',
              icon: Icons.play_circle_outline,
              onSeeAll: () => _openList(context, completed: false),
            ),
          ),
          SliverToBoxAdapter(child: _OngoingSection(source: _source)),
          const SliverToBoxAdapter(
            child: SectionHeader(
              title: 'Dari sumber lain',
              subtitle: 'Lihat juga dari sumber yang berbeda',
              icon: Icons.swap_horizontal_circle_outlined,
            ),
          ),
          SliverToBoxAdapter(child: _AltSourceSection(currentSource: _source)),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  void _openList(BuildContext context, {required bool completed}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OngoingScreen(source: _source, isCompleted: completed),
      ),
    );
  }

  void _navigateSchedule(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScheduleScreen(source: _source)),
    );
  }
}

class _LatestSection extends ConsumerWidget {
  final SourceId source;
  const _LatestSection({required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(latestProvider(source));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Rilisan Terbaru',
          subtitle: 'Dari ${source.label}',
          icon: Icons.new_releases_outlined,
        ),
        async.when(
          data: (list) {
            if (list.isEmpty) {
              return _EmptyHint(
                  text: 'Tidak ada rilisan terbaru dari ${source.label}.');
            }
            return SizedBox(
              height: 320,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: list.length > 10 ? 10 : list.length,
                itemBuilder: (context, i) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: SizedBox(
                      width: 130,
                      child: _PosterTile(anime: list[i]),
                    ),
                  );
                },
              ),
            );
          },
          loading: () => const SizedBox(
            height: 320,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _ErrorBox(message: '$e'),
        ),
      ],
    );
  }
}

class _OngoingSection extends ConsumerWidget {
  final SourceId source;
  const _OngoingSection({required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_ongoingProvider(source));
    return async.when(
      data: (list) {
        if (list.isEmpty) {
          return const _EmptyHint(text: 'Belum ada data ongoing.');
        }
        return AnimeGrid(
          animes: list.take(8).toList(),
          onTap: (a) => _goToDetail(context, a),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        );
      },
      loading: () => const SizedBox(
        height: 240,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _ErrorBox(message: '$e'),
    );
  }
}

class _AltSourceSection extends ConsumerWidget {
  final SourceId currentSource;
  const _AltSourceSection({required this.currentSource});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final other = SourceId.values.where((s) => s != currentSource).toList();
    return Column(
      children: [
        for (final s in other) ...[
          SectionHeader(
            title: s.label,
            subtitle: 'Rilisan terbaru',
            icon: Icons.swap_horizontal_circle,
          ),
          Consumer(builder: (context, ref, _) {
            final async = ref.watch(latestProvider(s));
            return async.when(
              data: (list) {
                if (list.isEmpty) return _EmptyHint(text: 'Tidak ada data dari ${s.label}.');
                return SizedBox(
                  height: 280,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: list.length > 8 ? 8 : list.length,
                    itemBuilder: (context, idx) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SizedBox(
                        width: 130,
                        child: _PosterTile(anime: list[idx]),
                      ),
                    ),
                  ),
                );
              },
              loading: () => const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _ErrorBox(message: '$e'),
            );
          }),
        ],
      ],
    );
  }
}

final _ongoingProvider =
    FutureProvider.autoDispose.family<List<Anime>, SourceId>((ref, source) async {
  return animeRepository.getOngoing(source, page: 1);
});

class _PosterTile extends StatelessWidget {
  final Anime anime;
  const _PosterTile({required this.anime});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: () => _goToDetail(context, anime),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: anime.cover == null || anime.cover!.isEmpty
                  ? Container(
                      color: scheme.surfaceContainerHighest,
                      child: const Center(child: Icon(Icons.movie)),
                    )
                  : Image.network(
                      anime.cover!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => Container(
                        color: scheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image, size: 32),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                anime.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _goToDetail(BuildContext context, Anime anime) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => DetailScreen(anime: anime)),
  );
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: scheme.outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: scheme.outline))),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Gagal memuat data: $message',
                style: TextStyle(color: scheme.onErrorContainer),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
