/// Cover komik dengan fallback berlapis:
/// 1) muat dengan Referer sumber, 2) coba ulang tanpa header kustom,
/// 3) jika URL cover kosong di daftar, ambil dari halaman detail (og:image).
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/models/comic.dart';
import '../../data/repositories/comic_repository.dart';

final Map<String, Future<String?>> _coverCache = {};

Future<String?> _fetchCover(Comic comic) {
  return _coverCache.putIfAbsent(comic.id, () async {
    try {
      final d = await comicRepository.scraperFor(comic.source).getDetail(comic);
      final c = d.cover;
      return (c == null || c.isEmpty) ? null : c;
    } catch (_) {
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
  bool _noHeaders = false;
  Future<String?>? _lazy;

  @override
  void initState() {
    super.initState();
    _initLazy();
  }

  @override
  void didUpdateWidget(covariant ComicCover old) {
    super.didUpdateWidget(old);
    if (old.comic.id != widget.comic.id || old.comic.cover != widget.comic.cover) {
      _noHeaders = false;
      _initLazy();
    }
  }

  bool get _hasCover => (widget.comic.cover ?? '').trim().isNotEmpty;

  void _initLazy() {
    _lazy = _hasCover ? null : _fetchCover(widget.comic);
  }

  Widget _placeholder(ColorScheme scheme, {IconData icon = Icons.menu_book}) => Container(
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(icon, size: 36, color: scheme.onSurfaceVariant),
      );

  Widget _image(String url, ColorScheme scheme) {
    final headers = _noHeaders ? null : comicRepository.scraperFor(widget.comic.source).imageHeaders;
    return CachedNetworkImage(
      key: ValueKey('$url|$_noHeaders'),
      imageUrl: url,
      httpHeaders: headers,
      fit: widget.fit,
      placeholder: (_, __) => _placeholder(scheme),
      errorWidget: (_, __, ___) {
        if (!_noHeaders) {
          // Sebagian CDN menolak Referer: coba ulang tanpa header kustom.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _noHeaders = true);
          });
          return _placeholder(scheme);
        }
        return _placeholder(scheme, icon: Icons.broken_image);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_hasCover) return _image(widget.comic.cover!.trim(), scheme);
    return FutureBuilder<String?>(
      future: _lazy,
      builder: (context, snap) {
        final url = snap.data;
        if (url != null && url.isNotEmpty) return _image(url, scheme);
        return _placeholder(scheme);
      },
    );
  }
}
