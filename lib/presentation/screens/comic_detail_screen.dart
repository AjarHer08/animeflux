/// Detail komik — info, bookmark, daftar chapter.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/models/comic.dart';
import '../../data/repositories/comic_repository.dart';
import 'browser_screen.dart';
import 'comic_reader_screen.dart';

class ComicDetailScreen extends StatefulWidget {
  final Comic comic;
  const ComicDetailScreen({super.key, required this.comic});

  @override
  State<ComicDetailScreen> createState() => _ComicDetailScreenState();
}

class _ComicDetailScreenState extends State<ComicDetailScreen> {
  late Future<Comic> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Comic> _load() =>
      comicRepository.scraperFor(widget.comic.source).getDetail(widget.comic);

  void _open(Comic comic, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ComicReaderScreen(comic: comic, index: index)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final headers = comicRepository.scraperFor(widget.comic.source).imageHeaders;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.comic.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.public),
            tooltip: 'Buka di browser ber-adblock',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => BrowserScreen(url: widget.comic.url, title: widget.comic.title)),
            ),
          ),
          ListenableBuilder(
            listenable: ComicLibrary.instance,
            builder: (context, _) {
              final bm = ComicLibrary.instance.isBookmarked(widget.comic.id);
              return IconButton(
                icon: Icon(bm ? Icons.bookmark : Icons.bookmark_outline, color: bm ? scheme.primary : null),
                tooltip: 'Bookmark',
                onPressed: () => ComicLibrary.instance.toggleBookmark(widget.comic),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<Comic>(
        future: _future,
        builder: (context, snap) {
          final comic = snap.data ?? widget.comic;
          final lib = ComicLibrary.instance;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 120,
                      height: 170,
                      child: comic.cover == null
                          ? Container(color: scheme.surfaceContainerHighest)
                          : CachedNetworkImage(
                              imageUrl: comic.cover!,
                              httpHeaders: headers,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(color: scheme.surfaceContainerHighest),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(comic.title,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(comic.source.label, style: TextStyle(color: scheme.primary, fontSize: 12)),
                        if (comic.status != null) Text('Status: ${comic.status}', style: const TextStyle(fontSize: 12)),
                        if (comic.type != null) Text('Tipe: ${comic.type}', style: const TextStyle(fontSize: 12)),
                        if (comic.author != null) Text('Author: ${comic.author}', style: const TextStyle(fontSize: 12)),
                        if (comic.rating != null) Text('Skor: ${comic.rating}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              if (comic.genres.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [for (final g in comic.genres) Chip(label: Text(g, style: const TextStyle(fontSize: 11)))],
                ),
              ],
              if ((comic.synopsis ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(comic.synopsis!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              ],
              const SizedBox(height: 16),
              if (snap.connectionState != ConnectionState.done)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else if (snap.hasError)
                Column(
                  children: [
                    Text('Gagal memuat detail: ${snap.error}', style: TextStyle(color: scheme.error)),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => setState(() => _future = _load()),
                      child: const Text('Coba lagi'),
                    ),
                  ],
                )
              else ...[
                ListenableBuilder(
                  listenable: lib,
                  builder: (context, _) {
                    if (comic.chapters.isEmpty) return const SizedBox.shrink();
                    final last = lib.lastRead(comic.id);
                    var idx = comic.chapters.length - 1; // chapter paling awal
                    var label = 'Mulai baca';
                    if (last != null) {
                      final i = comic.chapters.indexWhere((c) => c.url == last.url);
                      if (i >= 0) {
                        idx = i;
                        label = 'Lanjut: ${last.title}';
                      }
                    }
                    return FilledButton.icon(
                      icon: const Icon(Icons.menu_book),
                      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onPressed: () => _open(comic, idx),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text('Chapter (${comic.chapters.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (comic.chapters.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Daftar chapter tidak terbaca dari halaman ini (struktur situs mungkin berubah). '
                      'Gunakan tombol browser di pojok kanan atas.',
                      style: TextStyle(color: scheme.outline),
                    ),
                  ),
                ListenableBuilder(
                  listenable: lib,
                  builder: (context, _) => Column(
                    children: [
                      for (var i = 0; i < comic.chapters.length; i++)
                        ListTile(
                          dense: true,
                          title: Text(
                            comic.chapters[i].title,
                            style: TextStyle(
                              color: lib.isRead(comic.id, comic.chapters[i].url) ? scheme.outline : null,
                            ),
                          ),
                          subtitle: (comic.chapters[i].date ?? '').isEmpty ? null : Text(comic.chapters[i].date!),
                          trailing: lib.isRead(comic.id, comic.chapters[i].url)
                              ? const Icon(Icons.check, size: 18)
                              : null,
                          onTap: () => _open(comic, i),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
