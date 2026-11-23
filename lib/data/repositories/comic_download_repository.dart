/// Download komik: simpan semua gambar sebuah chapter ke penyimpanan app
/// supaya bisa dibaca offline. Berlaku untuk semua sumber (Komikstation,
/// Kiryuu, Komiku) karena memakai kontrak [ComicScraper] yang sama.
///
/// Lokasi: <folder app>/AnimeFlux/Komik/<sumber>_<judul>/<chapter>/001.jpg ...
/// Unduhan berjalan selama aplikasi terbuka (antrian berurutan per chapter,
/// 3 gambar paralel). Item yang terputus ditandai "Dijeda" dan bisa dilanjutkan.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/adblock/adblock_engine.dart';
import '../../core/theme/app_theme.dart' show sharedPreferencesInstance;
import '../../core/utils/logger.dart';
import '../../presentation/widgets/comic_image.dart';
import '../models/comic.dart';
import 'comic_repository.dart';
import 'download_repository.dart';

enum ComicDlStatus { queued, running, done, failed, paused }

class ComicDlChapter {
  final Map<String, dynamic> comicJson; // Comic.toJson()
  final String chapterTitle;
  final String chapterUrl;
  final String? number;
  final String? date;
  final int order; // posisi di daftar chapter asli (0 = terbaru)
  final String dir;
  ComicDlStatus status;
  int total;
  int done;
  String? error;

  ComicDlChapter({
    required this.comicJson,
    required this.chapterTitle,
    required this.chapterUrl,
    this.number,
    this.date,
    required this.order,
    required this.dir,
    this.status = ComicDlStatus.queued,
    this.total = 0,
    this.done = 0,
    this.error,
  });

  Comic get comic => Comic.fromJson(comicJson);
  String get comicId => comicJson['id'] as String;
  String get comicTitle => comicJson['title'] as String;
  ComicChapter get chapter =>
      ComicChapter(title: chapterTitle, url: chapterUrl, number: number, date: date);

  double? get progress => total <= 0 ? null : (done / total).clamp(0.0, 1.0).toDouble();

  Map<String, dynamic> toJson() => {
        'comic': comicJson,
        'title': chapterTitle,
        'url': chapterUrl,
        'number': number,
        'date': date,
        'order': order,
        'dir': dir,
        'status': status.name,
        'total': total,
        'done': done,
        'error': error,
      };

  factory ComicDlChapter.fromJson(Map<String, dynamic> j) {
    var st = ComicDlStatus.values.byName((j['status'] as String?) ?? 'paused');
    // Sisa sesi sebelumnya yang belum selesai -> dijeda (tidak jalan otomatis).
    if (st == ComicDlStatus.running || st == ComicDlStatus.queued) st = ComicDlStatus.paused;
    return ComicDlChapter(
      comicJson: Map<String, dynamic>.from(j['comic'] as Map),
      chapterTitle: j['title'] as String,
      chapterUrl: j['url'] as String,
      number: j['number'] as String?,
      date: j['date'] as String?,
      order: (j['order'] as num?)?.toInt() ?? 0,
      dir: j['dir'] as String,
      status: st,
      total: (j['total'] as num?)?.toInt() ?? 0,
      done: (j['done'] as num?)?.toInt() ?? 0,
      error: j['error'] as String?,
    );
  }
}

class ComicDownloads extends ChangeNotifier {
  ComicDownloads._() {
    _load();
  }
  static final ComicDownloads instance = ComicDownloads._();

  static const _key = 'comic_downloads_v1';
  static const _exts = ['.jpg', '.png', '.webp', '.gif', '.avif'];
  static const _parallel = 3;

  final List<ComicDlChapter> _items = [];
  bool _pumping = false;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 60),
    followRedirects: true,
    maxRedirects: 5,
  ));

  List<ComicDlChapter> get items => List.unmodifiable(_items);

  /// Daftar comicId yang punya unduhan (urutan terbaru dulu).
  List<String> get comicIds {
    final out = <String>[];
    for (final i in _items) {
      if (!out.contains(i.comicId)) out.add(i.comicId);
    }
    return out;
  }

  List<ComicDlChapter> forComic(String comicId) {
    final list = _items.where((e) => e.comicId == comicId).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  ComicDlChapter? find(String comicId, String chapterUrl) {
    for (final i in _items) {
      if (i.comicId == comicId && i.chapterUrl == chapterUrl) return i;
    }
    return null;
  }

  bool isDone(String comicId, String chapterUrl) =>
      find(comicId, chapterUrl)?.status == ComicDlStatus.done;

  // ------------------------------------------------------------ persistensi

  void _load() {
    for (final s in sharedPreferencesInstance.getStringList(_key) ?? const <String>[]) {
      try {
        _items.add(ComicDlChapter.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
  }

  Future<void> _persist() => sharedPreferencesInstance
      .setStringList(_key, _items.map((e) => jsonEncode(e.toJson())).toList());

  void _notify({bool force = true}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastNotify).inMilliseconds < 300) return;
    _lastNotify = now;
    notifyListeners();
  }

  // ------------------------------------------------------------- folder

  Future<Directory> _root() async {
    final base = await DownloadRepository(sharedPreferencesInstance).saveDir();
    final d = Directory('$base/Komik');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String _safe(String s, [int max = 60]) {
    var t = s.replaceAll(RegExp(r'[^\w\-\. ]'), '_').trim();
    if (t.isEmpty) t = 'komik';
    return t.length > max ? t.substring(0, max) : t;
  }

  // -------------------------------------------------------------- antrian

  /// Masukkan [chapters] ke antrian unduhan. Mengembalikan jumlah yang baru ditambahkan.
  Future<int> enqueue(Comic comic, Iterable<ComicChapter> chapters) async {
    final root = await _root();
    var added = 0;
    for (final ch in chapters) {
      final existing = find(comic.id, ch.url);
      if (existing != null) {
        if (existing.status == ComicDlStatus.failed || existing.status == ComicDlStatus.paused) {
          existing.status = ComicDlStatus.queued;
          existing.error = null;
          added++;
        }
        continue;
      }
      var order = comic.chapters.indexWhere((c) => c.url == ch.url);
      if (order < 0) order = 0;
      final dir = '${root.path}/${comic.source.name}_${_safe(comic.title)}/${_safe(ch.title, 80)}_$order';
      _items.add(ComicDlChapter(
        comicJson: comic.toJson(),
        chapterTitle: ch.title,
        chapterUrl: ch.url,
        number: ch.number,
        date: ch.date,
        order: order,
        dir: dir,
      ));
      added++;
    }
    await _persist();
    _notify();
    _pump();
    return added;
  }

  void pause(ComicDlChapter it) {
    if (it.status == ComicDlStatus.running || it.status == ComicDlStatus.queued) {
      it.status = ComicDlStatus.paused;
      _persist();
      _notify();
    }
  }

  void resume(ComicDlChapter it) {
    if (it.status == ComicDlStatus.paused || it.status == ComicDlStatus.failed) {
      it.status = ComicDlStatus.queued;
      it.error = null;
      _persist();
      _notify();
      _pump();
    }
  }

  void resumeAll() {
    for (final it in _items) {
      if (it.status == ComicDlStatus.paused || it.status == ComicDlStatus.failed) {
        it.status = ComicDlStatus.queued;
        it.error = null;
      }
    }
    _persist();
    _notify();
    _pump();
  }

  Future<void> remove(ComicDlChapter it) async {
    _items.remove(it);
    it.status = ComicDlStatus.paused; // hentikan worker yang masih berjalan
    await _deleteDir(it.dir);
    await _persist();
    _notify();
  }

  Future<void> removeComic(String comicId) async {
    final list = _items.where((e) => e.comicId == comicId).toList();
    for (final it in list) {
      _items.remove(it);
      it.status = ComicDlStatus.paused;
      await _deleteDir(it.dir);
    }
    await _persist();
    _notify();
  }

  Future<void> _deleteDir(String path) async {
    try {
      final d = Directory(path);
      if (await d.exists()) await d.delete(recursive: true);
    } catch (e) {
      logger.w('Hapus folder gagal: $e');
    }
  }

  // ------------------------------------------------------------ baca offline

  /// Path file halaman untuk chapter yang sudah selesai diunduh (urut), atau null.
  List<String>? localPages(String comicId, String chapterUrl) {
    final it = find(comicId, chapterUrl);
    if (it == null || it.status != ComicDlStatus.done) return null;
    try {
      final d = Directory(it.dir);
      if (!d.existsSync()) return null;
      final files = d
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.part'))
          .map((f) => f.path)
          .toList()
        ..sort();
      return files.isEmpty ? null : files;
    } catch (_) {
      return null;
    }
  }

  /// Comic bayangan untuk membaca offline dari layar Download (daftar chapter = yang sudah selesai).
  Comic offlineComic(String comicId) {
    final all = forComic(comicId).where((e) => e.status == ComicDlStatus.done).toList();
    final base = all.isNotEmpty ? all.first.comic : forComic(comicId).first.comic;
    return base.copyWith(chapters: [for (final e in all) e.chapter]);
  }

  // --------------------------------------------------------------- worker

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (true) {
        ComicDlChapter? next;
        for (final i in _items) {
          if (i.status == ComicDlStatus.queued) {
            next = i;
            break;
          }
        }
        if (next == null) break;
        await _runChapter(next);
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _runChapter(ComicDlChapter it) async {
    it.status = ComicDlStatus.running;
    it.error = null;
    _notify();
    try {
      final comic = it.comic;
      final scraper = comicRepository.scraperFor(comic.source);
      final pages = await scraper.getChapterPages(it.chapter);
      final engine = AdblockEngine.instance;
      final urls = pages.where((u) => !engine.isBlocked(u)).toList();
      if (urls.isEmpty) throw Exception('Tidak ada gambar terbaca di chapter ini');
      if (it.status != ComicDlStatus.running) return; // dijeda / dihapus saat memuat

      it.total = urls.length;
      it.done = 0;
      final dir = Directory(it.dir);
      await dir.create(recursive: true);

      var cursor = 0;
      var failures = 0;
      Future<void> worker() async {
        while (it.status == ComicDlStatus.running) {
          final i = cursor++;
          if (i >= urls.length) return;
          final ok = await _fetchOne(comic.source, urls[i], dir, i);
          if (it.status != ComicDlStatus.running) return;
          if (ok) {
            it.done++;
          } else {
            failures++;
          }
          _notify(force: false);
        }
      }

      await Future.wait([for (var k = 0; k < _parallel; k++) worker()]);

      if (it.status != ComicDlStatus.running) {
        await _persist();
        _notify();
        return;
      }
      if (failures == 0) {
        it.status = ComicDlStatus.done;
      } else {
        it.status = ComicDlStatus.failed;
        it.error = '$failures dari ${urls.length} gambar gagal diunduh';
      }
    } catch (e) {
      if (it.status == ComicDlStatus.running) {
        it.status = ComicDlStatus.failed;
        it.error = '$e';
      }
      logger.w('Download komik gagal (${it.chapterTitle}): $e');
    }
    await _persist();
    _notify();
  }

  Future<bool> _fetchOne(ComicSourceId source, String rawUrl, Directory dir, int index) async {
    final base = (index + 1).toString().padLeft(3, '0');
    for (final ext in _exts) {
      if (File('${dir.path}/$base$ext').existsSync()) return true;
    }
    final url = normalizeImageUrl(rawUrl);
    final attempts = <({String url, Map<String, String> headers})>[
      (url: url, headers: await ComicImageHeaders.build(source, url)),
      (url: url, headers: ComicImageHeaders.uaOnly()),
      (url: proxiedImageUrl(url), headers: const <String, String>{}),
    ];
    for (final a in attempts) {
      final tmp = File('${dir.path}/$base.part');
      try {
        await _dio.download(a.url, tmp.path, options: Options(headers: a.headers));
        final ext = await _sniff(tmp);
        if (ext == null) {
          await tmp.delete();
          continue; // bukan gambar (mis. halaman HTML blokir)
        }
        await tmp.rename('${dir.path}/$base$ext');
        return true;
      } catch (_) {
        try {
          if (tmp.existsSync()) tmp.deleteSync();
        } catch (_) {}
      }
    }
    return false;
  }

  /// Tentukan ekstensi dari byte awal file; null kalau bukan gambar.
  Future<String?> _sniff(File f) async {
    final raf = await f.open();
    try {
      final b = await raf.read(16);
      if (b.length < 12) return null;
      if (b[0] == 0xFF && b[1] == 0xD8) return '.jpg';
      if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return '.png';
      if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return '.gif';
      if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46) return '.webp';
      if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) return '.avif';
      return null;
    } finally {
      await raf.close();
    }
  }
}
