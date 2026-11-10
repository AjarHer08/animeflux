/// Scraper Kiryuu (tema kustom "kiryuu" — BUKAN MangaStream).
///
/// URL terverifikasi: seri `/manga/<slug>/`, chapter
/// `/manga/<slug>/chapter-N.<id>/`, daftar `/latest/`, `/advanced-search/`.
/// Class CSS tema ini tidak bisa diverifikasi dari luar, jadi parser berbasis
/// pola URL + fallback HTMX/AJAX. Jika daftar chapter / gambar kosong,
/// kemungkinan markup berubah — lihat README bagian "Menyesuaikan scraper".
library;

import 'package:html/dom.dart' as dom;

import '../../../core/utils/html_utils.dart';
import '../../../core/utils/http_client.dart';
import '../../../core/utils/logger.dart';
import '../../models/comic.dart';
import '../scraper_utils.dart';
import 'comic_scraper.dart';

class KiryuuScraper extends ComicScraper {
  final _http = HttpClient.instance;

  @override
  ComicSourceId get source => ComicSourceId.kiryuu;

  Future<List<Comic>> _firstNonEmpty(List<String> urls) async {
    Object? lastError;
    for (final u in urls) {
      try {
        final doc = parseHtml(await _http.getHtml(u));
        final list = parseComicLinks(doc, baseUrl, source);
        if (list.isNotEmpty) return list;
      } catch (e) {
        lastError = e;
        logger.w('Kiryuu $u gagal: $e');
      }
    }
    if (lastError != null) throw lastError;
    return const [];
  }

  @override
  Future<List<Comic>> getLatest({int page = 1}) => _firstNonEmpty([
        '$baseUrl/latest/?page=$page',
        '$baseUrl/?page=$page&pagedfor=latest',
      ]);

  @override
  Future<List<Comic>> getPopular({int page = 1}) => _firstNonEmpty([
        '$baseUrl/advanced-search/?order=popular&page=$page',
        '$baseUrl/?page=$page&pagedfor=project',
      ]);

  @override
  Future<List<Comic>> search(String query, {int page = 1}) {
    final q = Uri.encodeQueryComponent(query);
    return _firstNonEmpty([
      '$baseUrl/?s=$q',
      '$baseUrl/advanced-search/?title=$q&page=$page',
    ]);
  }

  /// Ambil fragmen HTMX (hx-get) yang memuat chapter / gambar.
  Future<List<dom.Document>> _htmxDocs(dom.Document doc, String keyword) async {
    final out = <dom.Document>[];
    for (final el in doc.querySelectorAll('[hx-get]')) {
      final u = el.attributes['hx-get'] ?? '';
      if (!u.toLowerCase().contains(keyword)) continue;
      try {
        out.add(parseHtml(await _http.getHtml(absoluteUrl(baseUrl, u))));
      } catch (e) {
        logger.w('Kiryuu hx-get gagal ($u): $e');
      }
    }
    return out;
  }

  @override
  Future<Comic> getDetail(Comic comic) async {
    final html = await _http.getHtml(comic.url);
    final doc = parseHtml(html);

    final title = cleanText(doc.querySelector('h1')?.text);
    final cover = metaContent(doc, 'og:image');
    final desc = metaContent(doc, 'og:description') ??
        cleanText(doc.querySelector('[itemprop="description"]')?.text);

    final genres = doc
        .querySelectorAll('a[href*="/genre/"], a[href*="/genres/"]')
        .map((e) => cleanText(e.text))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final info = <String, String>{};
    for (final el in doc.querySelectorAll('li, tr, dt, p, div')) {
      if (el.children.length > 4) continue;
      final t = cleanText(el.text);
      if (t.length < 80) applyInfoLine(t, info);
    }

    var chapters = parseChapterLinks(doc, baseUrl, onlyContaining: '/${comic.slug}/');

    if (chapters.isEmpty) {
      for (final frag in await _htmxDocs(doc, 'chapter')) {
        chapters = parseChapterLinks(frag, baseUrl, onlyContaining: '/${comic.slug}/');
        if (chapters.isNotEmpty) break;
      }
    }
    if (chapters.isEmpty) {
      // WordPress AJAX: ambil ID post dari markup lalu minta daftar chapter.
      final id = RegExp(r'''(?:manga[_-]?id|post[_-]?id|postid)["']?\s*[:=\-]\s*["']?(\d{3,})''')
          .firstMatch(html)
          ?.group(1);
      if (id != null) {
        final all = <ComicChapter>[];
        for (var p = 1; p <= 15; p++) {
          try {
            final frag = parseHtml(await _http.getHtml(
                '$baseUrl/wp-admin/admin-ajax.php?manga_id=$id&page=$p&action=chapter_list'));
            final part = parseChapterLinks(frag, baseUrl);
            final fresh = part.where((c) => !all.contains(c)).toList();
            if (fresh.isEmpty) break;
            all.addAll(fresh);
          } catch (_) {
            break;
          }
        }
        chapters = sortChapters(all);
      }
    }

    return comic.copyWith(
      title: title.isEmpty ? null : title,
      cover: cover,
      synopsis: desc.isEmpty ? null : desc,
      status: info['status'],
      type: info['type'],
      author: info['author'],
      genres: genres,
      chapters: chapters,
    );
  }

  @override
  Future<List<String>> getChapterPages(ComicChapter chapter) async {
    final html = await _http.getHtml(chapter.url);
    final doc = parseHtml(html);
    var pages = extractPageImages(doc, html, baseUrl);
    if (pages.length <= 1) {
      for (final frag in await _htmxDocs(doc, 'image')) {
        final more = extractPageImages(frag, frag.outerHtml, baseUrl);
        if (more.length > pages.length) pages = more;
      }
    }
    return pages;
  }
}
