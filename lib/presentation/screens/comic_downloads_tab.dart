/// Tab "Komik" di Download Manager — unduhan chapter dikelompokkan per komik.
library;

import 'package:flutter/material.dart';

import '../../data/repositories/comic_download_repository.dart';
import '../widgets/comic_cover.dart';
import 'comic_reader_screen.dart';

class ComicDownloadsTab extends StatelessWidget {
  const ComicDownloadsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: ComicDownloads.instance,
      builder: (context, _) {
        final dl = ComicDownloads.instance;
        final ids = dl.comicIds;
        if (ids.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.menu_book_outlined, size: 72, color: scheme.outline),
                  const SizedBox(height: 16),
                  Text('Belum ada komik diunduh', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Buka detail komik lalu ketuk ikon download untuk menyimpan chapter dan membacanya offline.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.outline, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 100),
          children: [for (final id in ids) _ComicGroup(comicId: id)],
        );
      },
    );
  }
}

class _ComicGroup extends StatelessWidget {
  final String comicId;
  const _ComicGroup({required this.comicId});

  static String _status(ComicDlChapter it) {
    switch (it.status) {
      case ComicDlStatus.done:
        return 'Selesai • ${it.total} halaman';
      case ComicDlStatus.running:
        return it.total > 0 ? 'Mengunduh ${it.done}/${it.total}' : 'Menyiapkan…';
      case ComicDlStatus.queued:
        return 'Antre';
      case ComicDlStatus.paused:
        return 'Dijeda';
      case ComicDlStatus.failed:
        return 'Gagal${it.error == null ? '' : ' — ${it.error}'}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final dl = ComicDownloads.instance;
    final chapters = dl.forComic(comicId);
    if (chapters.isEmpty) return const SizedBox.shrink();
    final first = chapters.first;
    final done = chapters.where((e) => e.status == ComicDlStatus.done).length;
    final active = chapters
        .where((e) => e.status == ComicDlStatus.running || e.status == ComicDlStatus.queued)
        .length;
    return ExpansionTile(
      key: PageStorageKey('dl_$comicId'),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(width: 44, height: 62, child: ComicCover(comic: first.comic)),
      ),
      title: Text(first.comicTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('$done selesai${active > 0 ? ' • $active berjalan' : ''} • ${chapters.length} chapter'),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: dl.resumeAll,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Lanjutkan semua'),
              ),
              TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Hapus semua unduhan komik ini?'),
                      content: Text(first.comicTitle),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
                      ],
                    ),
                  );
                  if (ok == true) await dl.removeComic(comicId);
                },
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Hapus semua'),
              ),
            ],
          ),
        ),
        for (final it in chapters)
          ListTile(
            dense: true,
            title: Text(it.chapterTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_status(it), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (it.status == ComicDlStatus.running)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(value: it.progress),
                  ),
              ],
            ),
            onTap: it.status != ComicDlStatus.done
                ? null
                : () {
                    final comic = dl.offlineComic(comicId);
                    final idx = comic.chapters.indexWhere((c) => c.url == it.chapterUrl);
                    if (idx < 0) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ComicReaderScreen(comic: comic, index: idx)),
                    );
                  },
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'pause') dl.pause(it);
                if (v == 'resume') dl.resume(it);
                if (v == 'remove') dl.remove(it);
              },
              itemBuilder: (_) => [
                if (it.status == ComicDlStatus.running || it.status == ComicDlStatus.queued)
                  const PopupMenuItem(value: 'pause', child: Text('Jeda')),
                if (it.status == ComicDlStatus.paused || it.status == ComicDlStatus.failed)
                  const PopupMenuItem(value: 'resume', child: Text('Lanjutkan / coba lagi')),
                const PopupMenuItem(value: 'remove', child: Text('Hapus (+ file)')),
              ],
            ),
          ),
      ],
    );
  }
}
