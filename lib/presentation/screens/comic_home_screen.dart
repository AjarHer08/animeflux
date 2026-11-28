/// Tab Komik — Terbaru / Populer / Bookmark + pencarian, per sumber.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/comic.dart';
import '../../data/repositories/comic_repository.dart';
import '../widgets/comic_cover.dart';
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
  ComicFilter _filter = const ComicFilter();
  String _query = '';
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Cari otomatis 600 ms setelah berhenti mengetik (min. 2 huruf); kolom
  /// kosong kembali ke daftar biasa. Enter tetap mencari seketika.
  void _onQueryChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      if (q.isEmpty || q.length >= 2) {
        if (q != _query) setState(() => _query = q);
      }
    });
  }

  int get _activeFilters =>
      (_filter.status != ComicStatusFilter.all ? 1 : 0) + (_filter.genre != null ? 1 : 0);

  Future<void> _openFilterSheet() async {
    final scraper = comicRepository.scraperFor(_source);
    final res = await showModalBottomSheet<ComicFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(
        initial: _filter,
        orders: scraper.supportedOrders,
        genresFuture: scraper.getGenres(),
      ),
    );
    if (res != null && mounted) setState(() => _filter = res);
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
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _debounce?.cancel();
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
                isDense: true,
              ),
              onChanged: (v) {
                _onQueryChanged(v);
                setState(() {}); // tampilkan/sembunyikan tombol hapus
              },
              onSubmitted: (v) {
                _debounce?.cancel();
                setState(() => _query = v.trim());
              },
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
                    onSelected: (_) => setState(() {
                      _source = s;
                      // Genre & urutan tiap situs berbeda -> reset yang tak berlaku.
                      final orders = comicRepository.scraperFor(s).supportedOrders;
                      _filter = _filter.copyWith(
                        clearGenre: true,
                        order: orders.contains(_filter.order) ? _filter.order : orders.first,
                      );
                    }),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final c in ComicCategory.values)
                        ChoiceChip(
                          label: Text(c.label),
                          selected: _filter.category == c,
                          onSelected: (_) => setState(() => _filter = _filter.copyWith(category: c)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Badge(
                  isLabelVisible: _activeFilters > 0,
                  label: Text('$_activeFilters'),
                  child: IconButton.filledTonal(
                    tooltip: 'Filter',
                    icon: const Icon(Icons.tune),
                    onPressed: _openFilterSheet,
                  ),
                ),
              ],
            ),
          ),
          if (_filter.genre != null || _filter.status != ComicStatusFilter.all)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (_filter.genre != null)
                      InputChip(
                        label: Text(_filter.genre!.label),
                        onDeleted: () => setState(() => _filter = _filter.copyWith(clearGenre: true)),
                      ),
                    if (_filter.status != ComicStatusFilter.all)
                      InputChip(
                        label: Text(_filter.status.label),
                        onDeleted: () =>
                            setState(() => _filter = _filter.copyWith(status: ComicStatusFilter.all)),
                      ),
                  ],
                ),
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
                _debounce?.cancel();
                _query = '';
                _searchCtrl.clear();
              }),
            ),
          ),
          Expanded(
            child: (_mode == _Mode.bookmark && _query.isEmpty)
                ? _BookmarkGrid(color: scheme.outline)
                : _PagedComicGrid(
                    key: ValueKey(
                        '${_source.name}-${_mode.name}-${_filter.category.name}-${_filter.status.name}-'
                        '${_filter.genre?.slug}-${_filter.order.name}-$_query'),
                    maxEmptyPages: _query.isNotEmpty ? 1 : 4,
                    loader: (page) {
                      final scraper = comicRepository.scraperFor(_source);
                      if (_query.isNotEmpty) return scraper.search(_query, page: page);
                      // Tombol Terbaru/Populer menentukan urutan, kecuali pengguna
                      // memilih urutan lain (A-Z / baru ditambahkan) lewat Filter.
                      var order = _filter.order;
                      if (order == ComicOrder.latest || order == ComicOrder.popular) {
                        order = _mode == _Mode.popular ? ComicOrder.popular : ComicOrder.latest;
                      }
                      return scraper.browse(page: page, filter: _filter.copyWith(order: order));
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

  /// Berapa halaman kosong/duplikat beruntun yang ditoleransi sebelum dianggap
  /// habis (filter di sisi aplikasi bisa mengosongkan satu halaman saja).
  final int maxEmptyPages;
  const _PagedComicGrid({super.key, required this.loader, this.maxEmptyPages = 1});

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
      final known = _items.map((e) => e.id).toSet();
      var fresh = <Comic>[];
      var page = _page;
      for (var tries = 0; tries < widget.maxEmptyPages; tries++) {
        page += 1;
        List<Comic> next;
        try {
          next = await widget.loader(page);
        } catch (e) {
          // Halaman > 1 yang gagal tidak membuang item yang sudah tampil.
          if (_items.isEmpty && tries == 0) rethrow;
          next = const [];
        }
        if (!mounted) return;
        fresh = [for (final c in next) if (!known.contains(c.id)) c];
        if (fresh.isNotEmpty) break;
      }
      setState(() {
        _page = page;
        if (fresh.isEmpty) {
          _end = true; // beberapa halaman beruntun kosong / duplikat = habis
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
                  if (_page > 0 && _items.isEmpty) _page = 0;
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
              child: ComicCover(comic: comic),
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


/// Bottom sheet filter: status, urutan, genre.
class _FilterSheet extends StatefulWidget {
  final ComicFilter initial;
  final List<ComicOrder> orders;
  final Future<List<ComicGenre>> genresFuture;
  const _FilterSheet({required this.initial, required this.orders, required this.genresFuture});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ComicFilter _f = widget.initial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget title(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
          child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
        );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              children: [
                title('Status'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final st in ComicStatusFilter.values)
                      ChoiceChip(
                        label: Text(st.label),
                        selected: _f.status == st,
                        onSelected: (_) => setState(() => _f = _f.copyWith(status: st)),
                      ),
                  ],
                ),
                title('Urutkan'),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Sesuai tab (Terbaru/Populer)'),
                      selected: _f.order == ComicOrder.latest || _f.order == ComicOrder.popular,
                      onSelected: (_) => setState(() => _f = _f.copyWith(order: ComicOrder.latest)),
                    ),
                    for (final o in widget.orders)
                      if (o == ComicOrder.az || o == ComicOrder.added)
                        ChoiceChip(
                          label: Text(o.label),
                          selected: _f.order == o,
                          onSelected: (_) => setState(() => _f = _f.copyWith(order: o)),
                        ),
                  ],
                ),
                title('Genre'),
                FutureBuilder<List<ComicGenre>>(
                  future: widget.genresFuture,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final genres = snap.data ?? const <ComicGenre>[];
                    return Wrap(
                      spacing: 8,
                      runSpacing: 0,
                      children: [
                        ChoiceChip(
                          label: const Text('Semua'),
                          selected: _f.genre == null,
                          onSelected: (_) => setState(() => _f = _f.copyWith(clearGenre: true)),
                        ),
                        for (final g in genres)
                          ChoiceChip(
                            label: Text(g.label),
                            selected: _f.genre == g,
                            onSelected: (_) => setState(() => _f = _f.copyWith(genre: g)),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => _f = ComicFilter(category: _f.category)),
                    child: Text('Reset', style: TextStyle(color: scheme.error)),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _f),
                    child: const Text('Terapkan'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
