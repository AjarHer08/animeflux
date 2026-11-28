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

  @override
  List<ComicOrder> get supportedOrders =>
      const [ComicOrder.latest, ComicOrder.popular, ComicOrder.az, ComicOrder.added];

  Future<List<Comic>> _htmlList(String url) async {
    final doc = parseHtml(await _http.getHtml(url));
    return parseComicLinks(doc, baseUrl, source);
  }

  // ------------------------------------------------------------ AJAX filter

  String? _nonce;

  /// Tema Kiryuu terbaru menjalankan filter/pencarian lewat
  /// `admin-ajax.php?action=advanced_search` dan butuh nonce dari
  /// `action=get_nonce`.
  Future<String?> _getNonce() async {
    if (_nonce != null) return _nonce;
    try {
      final html = await _http.getHtml(
          '$baseUrl/wp-admin/admin-ajax.php?type=search_form&action=get_nonce');
      final doc = parseHtml(html);
      final v = doc.querySelector('input[name="search_nonce"], input[name="nonce"]')?.attributes['value'] ??
          RegExp(r'''value=["']([a-zA-Z0-9]{6,})["']''').firstMatch(html)?.group(1);
      if (v != null && v.isNotEmpty) return _nonce = v;
    } catch (e) {
      logger.w('Kiryuu nonce gagal: $e');
    }
    return null;
  }

  String _ajaxOrderBy(ComicOrder o) {
    switch (o) {
      case ComicOrder.popular:
        return 'popular';
      case ComicOrder.az:
        return 'title';
      case ComicOrder.added:
        return 'created';
      case ComicOrder.latest:
        return 'updated';
    }
  }

  Future<List<Comic>> _ajaxSearch({
    required int page,
    ComicFilter filter = const ComicFilter(),
    String query = '',
  }) async {
    final nonce = await _getNonce();
    if (nonce == null) return const [];
    String arr(List<String> v) => '[${v.map((e) => '"$e"').join(',')}]';
    final html = await _http.postForm(
      '$baseUrl/wp-admin/admin-ajax.php?action=advanced_search',
      {
        'nonce': nonce,
        'inclusion': 'OR',
        'exclusion': 'OR',
        'page': '$page',
        'genre': arr([if (filter.genre != null) filter.genre!.slug]),
        'genre_exclude': '[]',
        'author': '',
        'artist': '',
        'project': '0',
        'type': arr([if (filter.category != ComicCategory.all) filter.category.slug]),
        'status': filter.status == ComicStatusFilter.all
            ? ''
            : (filter.status == ComicStatusFilter.ongoing ? 'ongoing' : 'completed'),
        'order': filter.order == ComicOrder.az ? 'asc' : 'desc',
        'orderby': _ajaxOrderBy(filter.order),
        'query': query,
      },
      headers: {'Referer': '$baseUrl/advanced-search/'},
    );
    if (html.trim().length < 50) return const [];
    return parseComicLinks(parseHtml(html), baseUrl, source);
  }

  // ------------------------------------------------------------- browse

  bool _matches(Comic c, ComicFilter f) {
    if (f.category != ComicCategory.all) {
      final t = (c.type ?? '').toLowerCase();
      if (t.isNotEmpty && t != f.category.slug) return false;
    }
    return true;
  }

  @override
  Future<List<Comic>> browse({int page = 1, ComicFilter filter = const ComicFilter()}) async {
    // 1) AJAX resmi (mendukung semua filter di sisi server).
    try {
      final r = await _ajaxSearch(page: page, filter: filter);
      if (r.isNotEmpty) return r;
    } catch (e) {
      logger.w('Kiryuu advanced_search gagal: $e');
    }

    // 2) HTML biasa. Genre -> arsip taksonomi /genre/<slug>/; selain itu
    //    /manga/ (populer/A-Z) atau /latest/. Tipe & status disaring di aplikasi.
    final g = filter.genre;
    final urls = <String>[
      if (g != null) ...[
        '$baseUrl/genre/${g.slug}/?page=$page',
        '$baseUrl/genre/${g.slug}/page/$page/',
      ] else if (filter.order == ComicOrder.latest) ...[
        '$baseUrl/latest/?page=$page',
        '$baseUrl/manga/?order=update&page=$page',
      ] else ...[
        '$baseUrl/manga/?order=${filter.order == ComicOrder.popular ? 'popular' : filter.order == ComicOrder.az ? 'title' : 'latest'}&page=$page',
        '$baseUrl/advanced-search/?order=${_ajaxOrderBy(filter.order)}&page=$page',
        '$baseUrl/latest/?page=$page',
      ],
    ];

    Object? lastError;
    var pool = <Comic>[];
    for (final u in urls) {
      try {
        pool = await _htmlList(u);
        if (pool.isNotEmpty) break;
      } catch (e) {
        lastError = e;
        logger.w('Kiryuu $u gagal: $e');
      }
    }
    if (pool.isEmpty && lastError != null && page <= 1) throw lastError;

    // Saring tipe di aplikasi.
    // (UI tetap lanjut ke halaman berikut walau satu halaman kosong setelah disaring.)
    return [for (final c in pool) if (_matches(c, filter)) c];
  }

  @override
  Future<List<Comic>> getLatest({int page = 1, ComicCategory category = ComicCategory.all}) =>
      browse(page: page, filter: ComicFilter(category: category));

  List<ComicGenre>? _genres;

  @override
  Future<List<ComicGenre>> getGenres() async {
    if (_genres != null) return _genres!;
    for (final u in ['$baseUrl/advanced-search/', '$baseUrl/manga/']) {
      try {
        final list = parseGenreOptions(parseHtml(await _http.getHtml(u)));
        if (list.length >= 5) return _genres = list;
      } catch (e) {
        logger.w('Genre Kiryuu $u gagal: $e');
      }
    }
    return kCommonGenres;
  }

  @override
  Future<List<Comic>> search(String query, {int page = 1}) async {
    final q = Uri.encodeQueryComponent(query);
    Object? lastError;

    // 1) AJAX (pencarian asli situs), 2) /?s= (hasil disaring relevansinya
    //    supaya sidebar "terbaru" tidak ikut terhitung hasil), 3) advanced-search.
    try {
      final r = await _ajaxSearch(page: page, query: query);
      final rel = filterRelevant(r, query);
      if (rel.isNotEmpty) return rel;
    } catch (e) {
      lastError = e;
      logger.w('Kiryuu cari (ajax) gagal: $e');
    }
    for (final u in [
      page <= 1 ? '$baseUrl/?s=$q' : '$baseUrl/page/$page/?s=$q',
      '$baseUrl/advanced-search/?title=$q&page=$page',
    ]) {
      try {
        final rel = filterRelevant(await _htmlList(u), query);
        if (rel.isNotEmpty) return rel;
      } catch (e) {
        lastError = e;
        logger.w('Kiryuu cari $u gagal: $e');
      }
    }
    if (lastError != null && page <= 1) throw lastError;
    return const [];
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

    final title = cleanTitle(doc.querySelector('h1')?.text);
    final cover = metaContent(doc, 'og:image');
    final desc = metaContent(doc, 'og:description') ??
        cleanText(doc.querySelector('[itemprop="description"]')?.text);

    final genres = uniqueTexts(doc, 'a[href*="/genre/"], a[href*="/genres/"]');

    final info = <String, String>{};
    for (final el in doc.querySelectorAll('li, tr, dt, p, div')) {
      if (el.children.length > 4) continue;
      final t = cleanText(el.text);
      if (t.length < 80) applyInfoLine(t, info);
    }

    var chapters = layeredChapters(doc, baseUrl, comic.slug);

    if (chapters.isEmpty) {
      for (final frag in await _htmxDocs(doc, 'chapter')) {
        chapters = layeredChapters(frag, baseUrl, comic.slug);
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
