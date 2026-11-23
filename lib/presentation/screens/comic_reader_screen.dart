/// Reader komik — scroll vertikal, prev/next chapter, tandai sudah dibaca,
/// ingat posisi baca (halaman + posisi di halaman) dan baca offline dari unduhan.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/adblock/adblock_engine.dart';
import '../../data/models/comic.dart';
import '../../data/repositories/comic_download_repository.dart';
import '../../data/repositories/comic_repository.dart';
import '../widgets/comic_image.dart';
import 'browser_screen.dart';

class ComicReaderScreen extends StatefulWidget {
  final Comic comic;
  final int index; // posisi di comic.chapters (terbaru dulu)

  /// Pulihkan posisi baca terakhir bila chapter ini yang terakhir dibaca.
  final bool resume;
  const ComicReaderScreen({
    super.key,
    required this.comic,
    required this.index,
    this.resume = true,
  });

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> with WidgetsBindingObserver {
  /// Tinggi sementara (x lebar layar) untuk halaman yang rasionya belum diketahui.
  static const _unknownRatio = 1.4;
  static const _footerExtent = 96.0;

  late int _index;
  List<String> _pages = [];
  List<String>? _local; // path file bila chapter sudah diunduh
  List<double?> _ratios = [];
  bool _loading = true;
  String? _error;
  bool _bars = true;

  ScrollController? _ctrl;
  double _width = 0;
  bool _restored = false; // posisi sudah dipulihkan -> boleh menyimpan
  Timer? _saveTimer;
  Timer? _ratioTimer;
  ({int page, double frac})? _lastPos; // dipakai saat dispose (controller sudah lepas)

  ComicChapter get _chapter => widget.comic.chapters[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _index = widget.index;
    _load(resume: widget.resume);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveNow();
    _saveTimer?.cancel();
    _ratioTimer?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveNow();
    }
  }

  // ------------------------------------------------------------- geometri

  double _extent(int i, double w) {
    final r = i < _ratios.length ? _ratios[i] : null;
    return w * ((r != null && r > 0) ? r : _unknownRatio);
  }

  double _offsetFor(int page, double frac, double w) {
    var off = 0.0;
    final last = _pages.isEmpty ? 0 : _pages.length - 1;
    final int p = page < 0 ? 0 : (page > last ? last : page);
    for (var i = 0; i < p; i++) {
      off += _extent(i, w);
    }
    return off + _extent(p, w) * frac;
  }

  ({int page, double frac}) _currentPos() {
    final c = _ctrl;
    if (c == null || !c.hasClients || _pages.isEmpty || _width <= 0) return (page: 0, frac: 0.0);
    var off = c.offset;
    for (var i = 0; i < _pages.length; i++) {
      final h = _extent(i, _width);
      if (off < h) return (page: i, frac: h > 0 ? (off / h).clamp(0.0, 1.0).toDouble() : 0.0);
      off -= h;
    }
    return (page: _pages.length - 1, frac: 1.0);
  }

  // ------------------------------------------------------------- simpan

  void _onScroll() {
    if (!_restored) return;
    _lastPos = _currentPos();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveNow);
  }

  void _saveNow() {
    if (!_restored || _pages.isEmpty || _loading || _error != null) return;
    final attached = _ctrl?.hasClients ?? false;
    final pos = attached ? _currentPos() : _lastPos;
    if (pos == null) return;
    ComicLibrary.instance.saveScroll(widget.comic.id, _chapter, pos.page, pos.frac);
  }

  void _persistRatios() {
    _ratioTimer?.cancel();
    final url = _chapter.url;
    _ratioTimer = Timer(const Duration(seconds: 1), () {
      ComicLibrary.instance.saveRatios(url, _ratios);
    });
  }

  void _onPageSize(int i, double w, double h) {
    if (!mounted || i >= _ratios.length || w <= 0) return;
    final ratio = h / w;
    final old = _ratios[i];
    if (old != null && (old - ratio).abs() < 0.002) return;
    final before = _extent(i, _width);
    // Halaman di atas layar berubah tinggi -> geser offset supaya yang sedang dibaca tidak melompat.
    final c = _ctrl;
    final topPage = _currentPos().page;
    setState(() => _ratios[i] = ratio);
    if (c != null && c.hasClients && i < topPage && _restored) {
      final delta = _extent(i, _width) - before;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (c.hasClients) c.jumpTo((c.offset + delta).clamp(0.0, c.position.maxScrollExtent).toDouble());
      });
    }
    _persistRatios();
  }

  // -------------------------------------------------------------- muat

  Future<void> _load({required bool resume}) async {
    _saveTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _pages = [];
      _restored = false;
      _lastPos = null;
    });
    try {
      final comicId = widget.comic.id;
      List<String> pages;
      List<String>? local = ComicDownloads.instance.localPages(comicId, _chapter.url);
      if (local != null) {
        pages = local;
      } else {
        final scraper = comicRepository.scraperFor(widget.comic.source);
        final raw = await scraper.getChapterPages(_chapter);
        // Buang gambar yang ternyata iklan (host terdaftar di filter).
        final engine = AdblockEngine.instance;
        pages = raw.where((u) => !engine.isBlocked(u)).toList();
      }
      if (!mounted) return;

      final saved = ComicLibrary.instance.ratios(_chapter.url);
      final ratios = List<double?>.filled(pages.length, null);
      if (saved != null && saved.length == pages.length) {
        for (var i = 0; i < saved.length; i++) {
          ratios[i] = saved[i] > 0 ? saved[i] : null;
        }
      }

      final pos = resume ? ComicLibrary.instance.scrollPos(comicId, _chapter.url) : null;
      _width = MediaQuery.sizeOf(context).width;
      _pages = pages;
      _local = local;
      _ratios = ratios;
      var initial = 0.0;
      if (pos != null && pages.isNotEmpty) {
        initial = _offsetFor(pos.page, pos.frac, _width);
      }

      final old = _ctrl;
      final ctrl = ScrollController(initialScrollOffset: initial)..addListener(_onScroll);
      _ctrl = ctrl;
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }

      setState(() {
        _loading = false;
        if (pages.isEmpty) {
          _error = 'Tidak ada gambar yang terbaca di chapter ini '
              '(struktur situs mungkin berubah, atau halaman diproteksi).';
        }
      });
      // Simpan posisi baru baru boleh setelah posisi lama dipulihkan (frame pertama).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ctrl == ctrl) {
          _restored = true;
          _lastPos = _currentPos();
        }
      });
      if (pages.isNotEmpty) {
        await ComicLibrary.instance.markRead(comicId, _chapter);
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
    _saveNow();
    setState(() => _index = newIndex);
    _load(resume: false);
  }

  // ------------------------------------------------------------- tampilan

  @override
  Widget build(BuildContext context) {
    _width = MediaQuery.sizeOf(context).width;
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
                if (_local != null)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.download_done, size: 20),
                  ),
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
                        FilledButton.tonal(
                          onPressed: () => _load(resume: false),
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : GestureDetector(
                  onTap: () => setState(() => _bars = !_bars),
                  child: ListView.builder(
                    key: ValueKey(_chapter.url),
                    controller: _ctrl,
                    cacheExtent: 2500,
                    itemCount: _pages.length + 1,
                    // Tinggi tiap item pasti -> posisi scroll bisa dipulihkan persis.
                    itemExtentBuilder: (i, dims) =>
                        i == _pages.length ? _footerExtent : _extent(i, dims.crossAxisExtent),
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
                      final local = _local;
                      return ComicNetImage(
                        key: ValueKey('${_chapter.url}#$i'),
                        source: widget.comic.source,
                        url: local != null ? '' : _pages[i],
                        localPath: local?[i],
                        fit: BoxFit.fitWidth,
                        width: double.infinity,
                        onSize: (w, h) => _onPageSize(i, w, h),
                        placeholderBuilder: (_) => const Center(child: CircularProgressIndicator()),
                        errorBuilder: (context, retry) => InkWell(
                          onTap: retry,
                          child: Center(
                            child: Text('Gambar ${i + 1} gagal dimuat — ketuk untuk coba lagi',
                                textAlign: TextAlign.center,
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
