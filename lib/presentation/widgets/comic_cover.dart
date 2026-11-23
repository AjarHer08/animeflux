/// Cover komik. Memakai [ComicNetImage] (fallback Referer+cookie -> UA saja ->
/// proxy). Bila URL cover kosong di daftar, ambil dari halaman detail.
library;

import 'package:flutter/material.dart';

import '../../data/models/comic.dart';
import '../../data/repositories/comic_repository.dart';
import 'comic_image.dart';

final Map<String, Future<String?>> _coverCache = {};

Future<String?> _fetchCover(Comic comic) {
  return _coverCache.putIfAbsent(comic.id, () async {
    try {
      final d = await comicRepository.scraperFor(comic.source).getDetail(comic);
      final c = d.cover;
      return (c == null || c.isEmpty) ? null : c;
    } catch (_) {
      // Jangan simpan kegagalan supaya bisa dicoba lagi nanti.
      _coverCache.remove(comic.id);
      return null;
    }
  });
}

class ComicCover extends StatefulWidget {
  final Comic comic;
  final BoxFit fit;
  const ComicCover({super.key, required this.comic, this.fit = BoxFit.cover});

  @override
  State<ComicCover> createState() => _ComicCoverState();
}

class _ComicCoverState extends State<ComicCover> {
  Future<String?>? _lazy;

  bool get _hasCover => (widget.comic.cover ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _initLazy();
  }

  @override
  void didUpdateWidget(covariant ComicCover old) {
    super.didUpdateWidget(old);
    if (old.comic.id != widget.comic.id || old.comic.cover != widget.comic.cover) {
      _initLazy();
    }
  }

  void _initLazy() {
    _lazy = _hasCover ? null : _fetchCover(widget.comic);
  }

  Widget _placeholder(ColorScheme scheme) => Container(
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.menu_book, size: 36, color: scheme.onSurfaceVariant),
      );

  Widget _image(String url) => ComicNetImage(
        source: widget.comic.source,
        url: url,
        fit: widget.fit,
        thumbWidth: 400,
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_hasCover) return _image(widget.comic.cover!.trim());
    return FutureBuilder<String?>(
      future: _lazy,
      builder: (context, snap) {
        final url = snap.data;
        if (url != null && url.isNotEmpty) return _image(url);
        return _placeholder(scheme);
      },
    );
  }
}
