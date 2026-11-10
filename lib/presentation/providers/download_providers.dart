/// Provider untuk download manager.
library;

import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_theme.dart' show sharedPreferencesInstance;
import '../../core/utils/logger.dart';
import '../../data/repositories/download_repository.dart';

final downloadRepositoryProvider = Provider<DownloadRepository>(
  (ref) => DownloadRepository(sharedPreferencesInstance),
);

class DownloadTasksNotifier extends StateNotifier<List<DownloadItem>> {
  DownloadTasksNotifier(this.repo) : super(const []) {
    refresh();
  }

  final DownloadRepository repo;

  /// Gabungkan daftar yang disimpan dengan status/progress terbaru dari
  /// flutter_downloader.
  Future<void> refresh() async {
    final items = repo.getAll();
    Map<String, DownloadTask> byId = {};
    try {
      final tasks = await FlutterDownloader.loadTasks() ?? const <DownloadTask>[];
      byId = {for (final t in tasks) t.taskId: t};
    } catch (e) {
      logger.w('loadTasks gagal: $e');
    }
    if (!mounted) return;
    state = [for (final i in items) i.withTask(byId[i.taskId])];
  }

  Future<void> enqueueUrl({
    required String animeId,
    required String animeTitle,
    required String episodeTitle,
    required String url,
    required String quality,
    String? cover,
    String? fileName,
    Map<String, String>? headers,
  }) async {
    try {
      await Permission.notification.request();
    } catch (_) {
      // izin notifikasi opsional — download tetap jalan tanpa notifikasi
    }
    await repo.enqueue(
      animeId: animeId,
      animeTitle: animeTitle,
      episodeTitle: episodeTitle,
      url: url,
      quality: quality,
      cover: cover,
      fileName: fileName,
      headers: headers,
    );
    await refresh();
  }

  Future<void> cancel(String taskId) async {
    await repo.cancel(taskId);
    await refresh();
  }

  Future<void> remove(String taskId) async {
    await repo.remove(taskId);
    await refresh();
  }

  Future<void> pause(String taskId) async {
    await repo.pause(taskId);
    await refresh();
  }

  Future<void> resume(String taskId) async {
    await repo.resume(taskId);
    await refresh();
  }
}

final downloadTasksProvider =
    StateNotifierProvider<DownloadTasksNotifier, List<DownloadItem>>((ref) {
  return DownloadTasksNotifier(ref.watch(downloadRepositoryProvider));
});

const String _kPortName = 'animeflux_downloader_port';

/// Callback flutter_downloader HARUS top-level/static + entry-point (jalan di
/// isolate terpisah). Closure akan membuat registerCallback melempar error
/// saat startup. Callback hanya meneruskan event ke isolate UI lewat port.
@pragma('vm:entry-point')
void downloadCallback(String id, dynamic status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName(_kPortName);
  send?.send(<dynamic>[id, progress]);
}

/// Dipanggil dari main().
void setupDownloadCallback(ProviderContainer container) {
  final port = ReceivePort();
  IsolateNameServer.removePortNameMapping(_kPortName);
  IsolateNameServer.registerPortWithName(port.sendPort, _kPortName);
  port.listen((_) {
    container.read(downloadTasksProvider.notifier).refresh();
  });
  FlutterDownloader.registerCallback(downloadCallback);
}
