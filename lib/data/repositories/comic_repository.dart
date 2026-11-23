/// Repository komik + perpustakaan lokal (bookmark & progres baca).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/theme/app_theme.dart' show sharedPreferencesInstance;
import '../models/comic.dart';
import '../scrapers/comic/comic_scraper.dart';
import '../scrapers/comic/kiryuu_scraper.dart';
import '../scrapers/comic/komiku_scraper.dart';
import '../scrapers/comic/mangastream_scraper.dart';

class ComicRepository {
  final Map<ComicSourceId, ComicScraper> _scrapers = {
    ComicSourceId.komikstation: MangaStreamScraper(),
    ComicSourceId.kiryuu: KiryuuScraper(),
    ComicSourceId.komiku: KomikuScraper(),
  };

  ComicScraper scraperFor(ComicSourceId id) => _scrapers[id]!;
}

final comicRepository = ComicRepository();

/// Bookmark + chapter terakhir dibaca (disimpan di SharedPreferences).
class ComicLibrary extends ChangeNotifier {
  ComicLibrary._() {
    _load();
  }
  static final ComicLibrary instance = ComicLibrary._();

  static const _bmKey = 'comic_bookmarks_v1';
  static const _progKey = 'comic_progress_v1';
  static const _ratioKey = 'comic_ratios_v1';

  final List<Comic> _bookmarks = [];
  final Map<String, Map<String, dynamic>> _progress = {};

  /// Rasio tinggi/lebar tiap halaman per chapter (kunci = URL chapter).
  /// Dipakai agar posisi scroll bisa dipulihkan persis walau gambar belum dimuat.
  final Map<String, List<double>> _ratios = {};

  List<Comic> get bookmarks => List.unmodifiable(_bookmarks);
  bool isBookmarked(String id) => _bookmarks.any((c) => c.id == id);

  void _load() {
    final prefs = sharedPreferencesInstance;
    for (final s in prefs.getStringList(_bmKey) ?? const <String>[]) {
      try {
        _bookmarks.add(Comic.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    try {
      final raw = prefs.getString(_progKey);
      if (raw != null) {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
          _progress[k] = Map<String, dynamic>.from(v as Map);
        });
      }
    } catch (_) {}
    try {
      final raw = prefs.getString(_ratioKey);
      if (raw != null) {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
          _ratios[k] = [for (final e in (v as List)) (e as num).toDouble()];
        });
      }
    } catch (_) {}
  }

  Future<void> toggleBookmark(Comic c) async {
    final i = _bookmarks.indexWhere((e) => e.id == c.id);
    if (i >= 0) {
      _bookmarks.removeAt(i);
    } else {
      _bookmarks.insert(0, c);
    }
    await sharedPreferencesInstance
        .setStringList(_bmKey, _bookmarks.map((e) => jsonEncode(e.toJson())).toList());
    notifyListeners();
  }

  ({String url, String title})? lastRead(String comicId) {
    final p = _progress[comicId];
    if (p == null || p['last'] == null) return null;
    return (url: p['last'] as String, title: (p['title'] as String?) ?? '');
  }

  bool isRead(String comicId, String chapterUrl) {
    final read = (_progress[comicId]?['read'] as List?)?.cast<String>() ?? const <String>[];
    return read.contains(chapterUrl);
  }

  Future<void> markRead(String comicId, ComicChapter ch) async {
    final p = _progress.putIfAbsent(comicId, () => <String, dynamic>{});
    final read = ((p['read'] as List?)?.cast<String>() ?? <String>[]).toList();
    if (!read.contains(ch.url)) read.add(ch.url);
    if (read.length > 600) read.removeRange(0, read.length - 600);
    p['read'] = read;
    p['last'] = ch.url;
    p['title'] = ch.title;
    await sharedPreferencesInstance.setString(_progKey, jsonEncode(_progress));
    notifyListeners();
  }

  // ---------------------------------------------------------- posisi baca

  /// Posisi terakhir di [chapterUrl]: nomor halaman (0-based) + fraksi 0..1 di halaman itu.
  ({int page, double frac})? scrollPos(String comicId, String chapterUrl) {
    final pos = _progress[comicId]?['pos'];
    if (pos is! Map || pos['url'] != chapterUrl) return null;
    final page = (pos['page'] as num?)?.toInt() ?? 0;
    final frac = (pos['frac'] as num?)?.toDouble() ?? 0.0;
    return (page: page, frac: frac.clamp(0.0, 1.0).toDouble());
  }

  /// Simpan posisi baca (tanpa notifyListeners supaya tidak membangun ulang UI saat scroll).
  Future<void> saveScroll(String comicId, ComicChapter ch, int page, double frac) async {
    final p = _progress.putIfAbsent(comicId, () => <String, dynamic>{});
    p['pos'] = {'url': ch.url, 'page': page, 'frac': double.parse(frac.toStringAsFixed(3))};
    p['last'] = ch.url;
    p['title'] = ch.title;
    await sharedPreferencesInstance.setString(_progKey, jsonEncode(_progress));
    notifyListeners();
  }

  List<double>? ratios(String chapterUrl) => _ratios[chapterUrl];

  Future<void> saveRatios(String chapterUrl, List<double?> ratios) async {
    if (ratios.every((r) => r == null)) return;
    _ratios.remove(chapterUrl); // pindah ke akhir (terbaru)
    _ratios[chapterUrl] = [for (final r in ratios) double.parse((r ?? 0).toStringAsFixed(3))];
    while (_ratios.length > 40) {
      _ratios.remove(_ratios.keys.first);
    }
    await sharedPreferencesInstance.setString(_ratioKey, jsonEncode(_ratios));
  }
}
