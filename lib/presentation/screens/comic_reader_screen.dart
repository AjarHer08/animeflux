/// Reader komik — scroll vertikal, prev/next chapter, tandai sudah dibaca.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/adblock/adblock_engine.dart';
import '../../data/models/comic.dart';
import '../../data/repositories/comic_repository.dart';
import 'browser_screen.dart';

class ComicReaderScreen extends StatefulWidget {
  final Comic comic;
  final int index; // posisi di comic.chapters (terbaru dulu)
  const ComicReaderScreen({super.key, required this.comic, required this.index});

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  late int _index;
  List<String> _pages = [];
  bool _loading = true;
  String? _error;
  bool _bars = true;

  ComicChapter get _chapter => widget.comic.chapters[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.index;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _pages = [];
    });
    try {
      final scraper = comicRepository.scraperFor(widget.comic.source);
      final pages = await scraper.getChapterPages(_chapter);
      // Buang gambar yang ternyata iklan (host terdaftar di filter).
      final engine = AdblockEngine.instance;
      final filtered = pages.where((u) => !engine.isBlocked(u)).toList();
      if (!mounted) return;
      setState(() {
        _pages = filtered;
        _loading = false;
        if (filtered.isEmpty) {
          _error = 'Tidak ada gambar yang terbaca di chapter ini '
              '(struktur situs mungkin berubah, atau halaman diproteksi).';
        }
      });
      if (filtered.isNotEmpty) {
        await ComicLibrary.instance.markRead(widget.comic.id, _chapter);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  void _go(int newIndex) {
    if (newIndex < 0 || newIndex >= widget.comic.chapters.length) return;
    setState(() => _index = newIndex);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final headers = comicRepository.scraperFor(widget.comic.source).imageHeaders;
    final hasNext = _index > 0; // chapter lebih baru
    final hasPrev = _index < widget.comic.chapters.length - 1;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _bars
          ? AppBar(
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              title: Text(_chapter.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  icon: const Icon(Icons.public),
                  tooltip: 'Buka chapter di browser',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => BrowserScreen(url: _chapter.url, title: _chapter.title)),
                  ),
                ),
              ],
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                        const SizedBox(height: 12),
                        FilledButton.tonal(onPressed: _load, child: const Text('Coba lagi')),
                      ],
                    ),
                  ),
                )
              : GestureDetector(
                  onTap: () => setState(() => _bars = !_bars),
                  child: ListView.builder(
                    cacheExtent: 2500,
                    itemCount: _pages.length + 1,
                    itemBuilder: (context, i) {
                      if (i == _pages.length) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: hasPrev ? () => _go(_index + 1) : null,
                                  icon: const Icon(Icons.chevron_left),
                                  label: const Text('Sebelumnya'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: hasNext ? () => _go(_index - 1) : null,
                                  icon: const Icon(Icons.chevron_right),
                                  label: const Text('Berikutnya'),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return CachedNetworkImage(
                        imageUrl: _pages[i],
                        httpHeaders: headers,
                        width: double.infinity,
                        fit: BoxFit.fitWidth,
                        placeholder: (_, __) => const SizedBox(
                          height: 400,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (_, __, ___) => SizedBox(
                          height: 200,
                          child: Center(
                            child: Text('Gambar ${i + 1} gagal dimuat',
                                style: const TextStyle(color: Colors.white54)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
