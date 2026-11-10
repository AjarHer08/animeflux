/// Download repository — kelola antrian download via flutter_downloader.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';

class DownloadItem {
  final String animeId;
  final String animeTitle;
  final String episodeTitle;
  final String url;
  final String quality; // '720p' / '1080p'
  final String? cover;
  final String taskId;
  final int? progress;
  final DownloadTaskStatus? status;

  const DownloadItem({
    required this.animeId,
    required this.animeTitle,
    required this.episodeTitle,
    required this.url,
    required this.quality,
    this.cover,
    required this.taskId,
    this.progress,
    this.status,
  });

  DownloadItem withTask(DownloadTask? t) => DownloadItem(
        animeId: animeId,
        animeTitle: animeTitle,
        episodeTitle: episodeTitle,
        url: url,
        quality: quality,
        cover: cover,
        taskId: taskId,
        progress: t?.progress ?? progress,
        status: t?.status ?? status,
      );

  Map<String, dynamic> toJson() => {
        'animeId': animeId,
        'animeTitle': animeTitle,
        'episodeTitle': episodeTitle,
        'url': url,
        'quality': quality,
        'cover': cover,
        'taskId': taskId,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
        animeId: json['animeId'] as String,
        animeTitle: json['animeTitle'] as String,
        episodeTitle: json['episodeTitle'] as String,
        url: json['url'] as String,
        quality: json['quality'] as String,
        cover: json['cover'] as String?,
        taskId: json['taskId'] as String,
      );
}

class DownloadRepository {
  DownloadRepository(this._prefs);
  final SharedPreferences _prefs;

  static const _key = 'downloads_v1';

  List<DownloadItem> getAll() {
    final raw = _prefs.getStringList(_key) ?? [];
    final out = <DownloadItem>[];
    for (final e in raw) {
      try {
        out.add(DownloadItem.fromJson(jsonDecode(e) as Map<String, dynamic>));
      } catch (_) {
        // entri rusak dilewati
      }
    }
    return out;
  }

  /// Folder tujuan. Pakai direktori app-specific (tidak butuh izin storage di
  /// Android 10+) dan pastikan foldernya ada.
  Future<String> saveDir() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/AnimeFlux');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  static String _extensionFor(String url, String? fileName) {
    final fromName = RegExp(r'\.(mp4|mkv|webm|avi|mov|zip|rar|7z)$', caseSensitive: false)
        .firstMatch(fileName ?? '');
    if (fromName != null) return '.${fromName.group(1)!.toLowerCase()}';
    final path = Uri.tryParse(url)?.path ?? url;
    final m = RegExp(r'\.(mp4|mkv|webm|avi|mov|zip|rar|7z)$', caseSensitive: false).firstMatch(path);
    return m != null ? '.${m.group(1)!.toLowerCase()}' : '.mp4';
  }

  Future<String> enqueue({
    required String animeId,
    required String animeTitle,
    required String episodeTitle,
    required String url,
    required String quality,
    String? cover,
    String? fileName,
    Map<String, String>? headers,
  }) async {
    final savedDir = await saveDir();
    final ext = _extensionFor(url, fileName);
    var base = (fileName != null && fileName.isNotEmpty)
        ? fileName.replaceAll(RegExp(r'\.[A-Za-z0-9]{2,4}$'), '')
        : '${animeTitle}_${episodeTitle}_$quality';
    base = base.replaceAll(RegExp(r'[^\w\-\. ]'), '_');
    if (base.length > 120) base = base.substring(0, 120);
    final name = '$base$ext';

    final origin = Uri.tryParse(url)?.origin ?? url;
    final taskId = await FlutterDownloader.enqueue(
      url: url,
      savedDir: savedDir,
      fileName: name,
      headers: {
        'User-Agent': kDesktopUserAgents[0],
        'Referer': '$origin/',
        ...?headers,
      },
      showNotification: true,
      openFileFromNotification: true,
      saveInPublicStorage: false,
    );
    if (taskId == null) throw Exception('Gagal enqueue download');
    final items = getAll();
    items.insert(
      0,
      DownloadItem(
        animeId: animeId,
        animeTitle: animeTitle,
        episodeTitle: episodeTitle,
        url: url,
        quality: quality,
        cover: cover,
        taskId: taskId,
      ),
    );
    await _saveItems(items);
    return taskId;
  }

  Future<void> cancel(String taskId) async {
    await FlutterDownloader.cancel(taskId: taskId);
    final items = getAll()..removeWhere((e) => e.taskId == taskId);
    await _saveItems(items);
  }

  Future<void> remove(String taskId) async {
    await FlutterDownloader.remove(taskId: taskId, shouldDeleteContent: true);
    final items = getAll()..removeWhere((e) => e.taskId == taskId);
    await _saveItems(items);
  }

  Future<void> pause(String taskId) => FlutterDownloader.pause(taskId: taskId);

  Future<void> resume(String taskId) async {
    final newId = await FlutterDownloader.resume(taskId: taskId);
    if (newId != null && newId != taskId) {
      // flutter_downloader memberi taskId baru saat resume.
      final items = getAll();
      final i = items.indexWhere((e) => e.taskId == taskId);
      if (i >= 0) {
        final old = items[i];
        items[i] = DownloadItem(
          animeId: old.animeId,
          animeTitle: old.animeTitle,
          episodeTitle: old.episodeTitle,
          url: old.url,
          quality: old.quality,
          cover: old.cover,
          taskId: newId,
        );
        await _saveItems(items);
      }
    }
  }

  Future<void> _saveItems(List<DownloadItem> items) async {
    await _prefs.setStringList(
      _key,
      items.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }
}
