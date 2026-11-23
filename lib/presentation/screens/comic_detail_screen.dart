/// Detail komik — info, bookmark, daftar chapter.
library;

import 'package:flutter/material.dart';
import '../widgets/comic_cover.dart';
import '../widgets/glass.dart';

import '../../data/models/comic.dart';
import '../../data/repositories/comic_download_repository.dart';
import '../../data/repositories/comic_repository.dart';
import 'browser_screen.dart';
import 'comic_reader_screen.dart';
import 'downloads_screen.dart';

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

  void _snack(String msg, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action));
  }

  Future<void> _enqueue(Comic comic, List<ComicChapter> chapters) async {
    if (chapters.isEmpty) {
      _snack('Tidak ada chapter untuk diunduh');
      return;
    }
    // Chapter paling awal diunduh lebih dulu supaya bisa dibaca berurutan.
    final ordered = List<ComicChapter>.of(chapters)
      ..sort((a, b) => comic.chapters.indexOf(b).compareTo(comic.chapters.indexOf(a)));
    final n = await ComicDownloads.instance.enqueue(comic, ordered);
    _snack(
      n == 0 ? 'Chapter sudah ada di unduhan' : '$n chapter masuk antrian unduhan',
      action: SnackBarAction(
        label: 'Lihat',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DownloadsScreen(initialTab: 1)),
        ),
      ),
    );
  }

  Future<void> _downloadMenu(Comic comic) async {
    if (comic.chapters.isEmpty) {
      _snack('Daftar chapter belum termuat');
      return;
    }
    final lib = ComicLibrary.instance;
    final unread = [for (final c in comic.chapters) if (!lib.isRead(comic.id, c.url)) c];
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: Text('Semua chapter (${comic.chapters.length})'),
              onTap: () => Navigator.pop(ctx, 'all'),
            ),
            ListTile(
              leading: const Icon(Icons.mark_chat_unread_outlined),
              title: Text('Yang belum dibaca (${unread.length})'),
              onTap: () => Navigator.pop(ctx, 'unread'),
            ),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('Pilih chapter…'),
              onTap: () => Navigator.pop(ctx, 'pick'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'all') {
      await _enqueue(comic, comic.chapters);
    } else if (choice == 'unread') {
      await _enqueue(comic, unread);
    } else {
      final picked = await _pickChapters(comic);
      if (picked != null) await _enqueue(comic, picked);
    }
  }

  Future<List<ComicChapter>?> _pickChapters(Comic comic) {
    final selected = <ComicChapter>{};
    return showDialog<List<ComicChapter>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Pilih chapter'),
          contentPadding: const EdgeInsets.only(top: 12),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.sizeOf(ctx).height * 0.55,
            child: ListView.builder(
              itemCount: comic.chapters.length,
              itemBuilder: (_, i) {
                final c = comic.chapters[i];
                return CheckboxListTile(
                  dense: true,
                  value: selected.contains(c),
                  title: Text(c.title),
                  onChanged: (v) => setLocal(() {
                    if (v == true) {
                      selected.add(c);
                    } else {
                      selected.remove(c);
                    }
                  }),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setLocal(() {
                if (selected.length == comic.chapters.length) {
                  selected.clear();
                } else {
                  selected.addAll(comic.chapters);
                }
              }),
              child: Text(selected.length == comic.chapters.length ? 'Kosongkan' : 'Pilih semua'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            FilledButton(
              onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, selected.toList()),
              child: Text('Unduh (${selected.length})'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(ComicDlChapter it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus unduhan?'),
        content: Text('${it.chapterTitle} akan dihapus dari penyimpanan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) await ComicDownloads.instance.remove(it);
  }

  Widget _downloadButton(Comic comic, ComicChapter ch, ColorScheme scheme) {
    final dl = ComicDownloads.instance;
    final it = dl.find(comic.id, ch.url);
    Widget btn(Widget icon, VoidCallback onTap, String tip) => IconButton(
          icon: icon,
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
        );
    if (it == null) {
      return btn(const Icon(Icons.download_outlined, size: 20), () => _enqueue(comic, [ch]), 'Unduh');
    }
    switch (it.status) {
      case ComicDlStatus.done:
        return btn(Icon(Icons.download_done, size: 20, color: scheme.primary),
            () => _confirmRemove(it), 'Sudah diunduh (ketuk untuk hapus)');
      case ComicDlStatus.running:
      case ComicDlStatus.queued:
        return btn(
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              value: it.status == ComicDlStatus.running ? it.progress : null,
            ),
          ),
          () => dl.pause(it),
          'Mengunduh (ketuk untuk jeda)',
        );
      case ComicDlStatus.paused:
        return btn(const Icon(Icons.play_circle_outline, size: 20), () => dl.resume(it), 'Lanjutkan unduhan');
      case ComicDlStatus.failed:
        return btn(Icon(Icons.refresh, size: 20, color: scheme.error), () => dl.resume(it),
            it.error ?? 'Gagal — ketuk untuk coba lagi');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: GlassAppBar(
        title: Text(widget.comic.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          FutureBuilder<Comic>(
            future: _future,
            builder: (context, snap) => IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Download chapter',
              onPressed: snap.hasData ? () => _downloadMenu(snap.data!) : null,
            ),
          ),
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
                      child: ComicCover(comic: comic),
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
                        final pos = lib.scrollPos(comic.id, last.url);
                        label = pos == null
                            ? 'Lanjut: ${last.title}'
                            : 'Lanjut: ${last.title} (hal. ${pos.page + 1})';
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
                  listenable: Listenable.merge([lib, ComicDownloads.instance]),
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (lib.isRead(comic.id, comic.chapters[i].url))
                                const Icon(Icons.check, size: 18),
                              _downloadButton(comic, comic.chapters[i], scheme),
                            ],
                          ),
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
