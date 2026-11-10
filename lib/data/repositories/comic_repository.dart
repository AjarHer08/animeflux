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

  final List<Comic> _bookmarks = [];
  final Map<String, Map<String, dynamic>> _progress = {};

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
}
