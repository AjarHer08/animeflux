/// Ongoing screen — list ongoing atau completed dari sumber terpilih.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/models/anime.dart';
import '../../data/repositories/anime_repository.dart';
import '../widgets/anime_grid.dart';
import '../widgets/source_selector.dart';
import 'detail_screen.dart';

class OngoingScreen extends ConsumerStatefulWidget {
  final SourceId source;
  final bool isCompleted;
  const OngoingScreen({super.key, required this.source, this.isCompleted = false});

  @override
  ConsumerState<OngoingScreen> createState() => _OngoingScreenState();
}

class _OngoingScreenState extends ConsumerState<OngoingScreen> {
  late SourceId _source;
  late bool _isCompleted;
  List<Anime> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _source = widget.source;
    _isCompleted = widget.isCompleted;
    _loadFirst();
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = _isCompleted
          ? await animeRepository.getCompleted(_source, page: 1)
          : await animeRepository.getOngoing(_source, page: 1);
      _items = list;
      _page = 1;
      _hasMore = list.isNotEmpty;
    } catch (e) {
      _items = [];
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final next = _isCompleted
          ? await animeRepository.getCompleted(_source, page: _page + 1)
          : await animeRepository.getOngoing(_source, page: _page + 1);
      if (next.isEmpty) {
        _hasMore = false;
      } else {
        _items = [..._items, ...next];
        _page += 1;
      }
    } catch (_) {
      // Gagal memuat halaman berikutnya: biarkan list sekarang, coba lagi saat scroll.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isCompleted ? 'Completed' : 'Ongoing'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SourceSelector(
                    value: _source,
                    onChanged: (s) {
                      setState(() => _source = s);
                      _loadFirst();
                    },
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Ongoing')),
                      ButtonSegment(value: true, label: Text('Completed')),
                    ],
                    selected: {_isCompleted},
                    onSelectionChanged: (s) {
                      setState(() => _isCompleted = s.first);
                      _loadFirst();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is ScrollEndNotification && n.metrics.atEdge && n.metrics.pixels > 0) {
                    _loadMore();
                  }
                  return false;
                },
                child: _items.isEmpty
                    ? _loading
                        ? const Center(child: CircularProgressIndicator())
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _error != null
                                        ? 'Gagal memuat dari ${_source.label}:\n$_error'
                                        : 'Tidak ada data untuk ${_source.label}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Theme.of(context).colorScheme.outline),
                                  ),
                                  if (_error != null) ...[
                                    const SizedBox(height: 12),
                                    FilledButton.tonal(
                                      onPressed: _loadFirst,
                                      child: const Text('Coba lagi'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                    : Stack(
                        children: [
                          AnimeGrid(
                            animes: _items,
                            onTap: (a) => _goToDetail(context, a),
                          ),
                          if (_loading && _items.isNotEmpty)
                            const Positioned(
                              bottom: 16,
                              left: 0,
                              right: 0,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _goToDetail(BuildContext context, Anime anime) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailScreen(anime: anime)),
    );
  }
}
