/// Tab Komik — Terbaru / Populer / Bookmark + pencarian, per sumber.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/models/comic.dart';
import '../../data/repositories/comic_repository.dart';
import 'comic_detail_screen.dart';

enum _Mode { latest, popular, bookmark }

class ComicHomeScreen extends StatefulWidget {
  const ComicHomeScreen({super.key});

  @override
  State<ComicHomeScreen> createState() => _ComicHomeScreenState();
}

class _ComicHomeScreenState extends State<ComicHomeScreen> {
  ComicSourceId _source = ComicSourceId.komikstation;
  _Mode _mode = _Mode.latest;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Komik',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Cari di ${_source.label}...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
                isDense: true,
              ),
              onSubmitted: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final s in ComicSourceId.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _source == s,
                    onSelected: (_) => setState(() => _source = s),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(value: _Mode.latest, label: Text('Terbaru'), icon: Icon(Icons.new_releases_outlined)),
                ButtonSegment(value: _Mode.popular, label: Text('Populer'), icon: Icon(Icons.local_fire_department_outlined)),
                ButtonSegment(value: _Mode.bookmark, label: Text('Bookmark'), icon: Icon(Icons.bookmark_outline)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() {
                _mode = s.first;
                _query = '';
                _searchCtrl.clear();
              }),
            ),
          ),
          Expanded(
            child: (_mode == _Mode.bookmark && _query.isEmpty)
                ? _BookmarkGrid(color: scheme.outline)
                : _PagedComicGrid(
                    key: ValueKey('${_source.name}-${_mode.name}-$_query'),
                    loader: (page) {
                      final scraper = comicRepository.scraperFor(_source);
                      if (_query.isNotEmpty) return scraper.search(_query, page: page);
                      return _mode == _Mode.popular
                          ? scraper.getPopular(page: page)
                          : scraper.getLatest(page: page);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _BookmarkGrid extends StatelessWidget {
  final Color color;
  const _BookmarkGrid({required this.color});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ComicLibrary.instance,
      builder: (context, _) {
        final list = ComicLibrary.instance.bookmarks;
        if (list.isEmpty) {
          return Center(
            child: Text('Belum ada bookmark.\nBuka komik lalu tekan ikon bookmark.',
                textAlign: TextAlign.center, style: TextStyle(color: color)),
          );
        }
        return _ComicGridView(comics: list);
      },
    );
  }
}

class _PagedComicGrid extends StatefulWidget {
  final Future<List<Comic>> Function(int page) loader;
  const _PagedComicGrid({super.key, required this.loader});

  @override
  State<_PagedComicGrid> createState() => _PagedComicGridState();
}

class _PagedComicGridState extends State<_PagedComicGrid> {
  final List<Comic> _items = [];
  final _scroll = ScrollController();
  int _page = 0;
  bool _loading = false;
  bool _end = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || _end) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final next = await widget.loader(_page + 1);
      if (!mounted) return;
      final known = _items.map((e) => e.id).toSet();
      final fresh = next.where((c) => !known.contains(c.id)).toList();
      setState(() {
        _page += 1;
        if (fresh.isEmpty) {
          _end = true; // halaman kosong / hanya duplikat = habis
        } else {
          _items.addAll(fresh);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error != null ? 'Gagal memuat:\n$_error' : 'Tidak ada hasil.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () {
                  _end = false;
                  _loadMore();
                },
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }
    return _ComicGridView(comics: _items, controller: _scroll, loading: _loading);
  }
}

class _ComicGridView extends StatelessWidget {
  final List<Comic> comics;
  final ScrollController? controller;
  final bool loading;
  const _ComicGridView({required this.comics, this.controller, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              childAspectRatio: 0.58,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => ComicCard(comic: comics[i]),
              childCount: comics.length,
            ),
          ),
        ),
        if (loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

class ComicCard extends StatelessWidget {
  final Comic comic;
  const ComicCard({super.key, required this.comic});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final headers = comicRepository.scraperFor(comic.source).imageHeaders;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ComicDetailScreen(comic: comic)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: comic.cover == null
                  ? Container(
                      color: scheme.surfaceContainerHighest,
                      child: const Icon(Icons.menu_book, size: 40),
                    )
                  : CachedNetworkImage(
                      imageUrl: comic.cover!,
                      httpHeaders: headers,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: scheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(comic.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  if ((comic.latestChapter ?? '').isNotEmpty)
                    Text(comic.latestChapter!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: scheme.primary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
