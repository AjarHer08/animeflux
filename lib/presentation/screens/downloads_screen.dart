/// Downloads screen — list download yang sedang berjalan & selesai.
library;

import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/download_providers.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final items = ref.watch(downloadTasksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Download Manager')),
      body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: items.isEmpty
                ? _EmptyState(
                    icon: Icons.download_outlined,
                    title: 'Belum ada download',
                    description: 'Download episode akan muncul di sini. Buka episode untuk mulai download.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = items[i];
                      return ListTile(
                        leading: const Icon(Icons.video_file),
                        title: Text(
                          '${item.animeTitle} — ${item.episodeTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => FlutterDownloader.open(taskId: item.taskId),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${item.quality} • ${_statusLabel(item.status)}'),
                            if (item.status == DownloadTaskStatus.running)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: LinearProgressIndicator(value: (item.progress ?? 0) / 100),
                              ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            switch (v) {
                              case 'pause':
                                await ref.read(downloadTasksProvider.notifier).pause(item.taskId);
                                break;
                              case 'resume':
                                await ref.read(downloadTasksProvider.notifier).resume(item.taskId);
                                break;
                              case 'cancel':
                                await ref.read(downloadTasksProvider.notifier).cancel(item.taskId);
                                break;
                              case 'remove':
                                await ref.read(downloadTasksProvider.notifier).remove(item.taskId);
                                break;
                            }
                            ref.read(downloadTasksProvider.notifier).refresh();
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'pause', child: Text('Pause')),
                            PopupMenuItem(value: 'resume', child: Text('Resume')),
                            PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                            PopupMenuItem(value: 'remove', child: Text('Hapus (+ file)')),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      ),
    );
  }

  static String _statusLabel(DownloadTaskStatus? s) {
    if (s == DownloadTaskStatus.running) return 'Mengunduh';
    if (s == DownloadTaskStatus.complete) return 'Selesai';
    if (s == DownloadTaskStatus.failed) return 'Gagal';
    if (s == DownloadTaskStatus.paused) return 'Dijeda';
    if (s == DownloadTaskStatus.enqueued) return 'Antre';
    if (s == DownloadTaskStatus.canceled) return 'Dibatalkan';
    return '—';
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: scheme.outline),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
