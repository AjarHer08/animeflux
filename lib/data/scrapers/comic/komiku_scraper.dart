/// Scraper Komiku (komiku.org). Daftar dimuat dari api.komiku.org.
///
/// Situs ini memblokir request non-browser (bot detection) — HttpClient
/// otomatis jatuh ke WebView headless. Selector `.bge`, `#Daftar_Chapter`,
/// `#Baca_Komik` berasal dari struktur umum Komiku dan tidak bisa
/// diverifikasi dari luar; fallback berbasis pola URL tetap tersedia.
library;

import '../../../core/utils/html_utils.dart';
import '../../../core/utils/http_client.dart';
import '../../../core/utils/logger.dart';
import '../../models/comic.dart';
import '../scraper_utils.dart';
import 'comic_scraper.dart';

class KomikuScraper extends ComicScraper {
  final _http = HttpClient.instance;

  @override
  ComicSourceId get source => ComicSourceId.komiku;

  String get _api {
    final host = Uri.tryParse(baseUrl)?.host ?? 'komiku.org';
    return 'https://api.$host';
  }

  Future<List<Comic>> _list(
    List<String> urls, {
    String? searchQuery,
    ComicStatusFilter status = ComicStatusFilter.all,
    ComicCategory category = ComicCategory.all,
    bool quietEmpty = false,
  }) async {
    Object? lastError;
    for (final u in urls) {
      try {
        final doc = parseHtml(await _http.getHtml(u));
        final out = <Comic>[];
        final seen = <String>{};
        for (final card in doc.querySelectorAll('.bge')) {
          final a = card.querySelector('.bgei a[href], a[href]');
          final href = a?.attributes['href'];
          if (a == null || href == null) continue;
          final abs = absoluteUrl(baseUrl, href);
          final slug = slugOf(abs);
          if (!seen.add(slug)) continue;
          final title = cleanText(card.querySelector('.kan h3, h3')?.text);
          out.add(Comic(
            id: Comic.makeId(source, slug),
            source: source,
            title: title.isEmpty ? titleFromSlug(slug) : title,
            slug: slug,
            url: abs,
            cover: coverIn(card.querySelector('.bgei'), baseUrl) ?? coverIn(card, baseUrl),
            type: cleanText(card.querySelector('.tpe1_inf b')?.text),
            latestChapter: cleanText(card.querySelector('.new1 a span:last-child, .new1')?.text),
          ));
        }
        if (out.isNotEmpty) return _post(out, status, category);
        var generic = parseComicLinks(doc, baseUrl, source);
        if (searchQuery != null) generic = filterRelevant(generic, searchQuery);
        if (generic.isNotEmpty) return _post(generic, status, category);
      } catch (e) {
        lastError = e;
        logger.w('Komiku $u gagal: $e');
      }
    }
    if (lastError != null && !quietEmpty) throw lastError;
    return const [];
  }

  /// Jaga-jaga bila API mengabaikan parameter `tipe`: saring ulang di aplikasi
  /// hanya jika badge tipe terbaca pada kartu.
  List<Comic> _post(List<Comic> list, ComicStatusFilter status, ComicCategory category) {
    if (category == ComicCategory.all) return list;
    final typed = list.where((c) => (c.type ?? '').isNotEmpty).toList();
    if (typed.isEmpty) return list;
    final wanted = category.slug.toLowerCase();
    final ok = [for (final c in list) if ((c.type ?? '').toLowerCase() == wanted) c];
    return ok.isEmpty ? list : ok;
  }

  @override
  List<ComicOrder> get supportedOrders =>
      const [ComicOrder.latest, ComicOrder.popular, ComicOrder.added];

  String _orderBy(ComicOrder o) {
    switch (o) {
      case ComicOrder.popular:
        return 'meta_value_num';
      case ComicOrder.added:
        return 'date';
      case ComicOrder.latest:
      case ComicOrder.az:
        return 'modified';
    }
  }

  /// API Komiku: `/manga/page/N/?orderby=..&tipe=..&genre=..&status=..`
  /// (status: `ongoing` | `end`).
  @override
  Future<List<Comic>> browse({int page = 1, ComicFilter filter = const ComicFilter()}) {
    final q = <String>['orderby=${_orderBy(filter.order)}'];
    if (filter.category != ComicCategory.all) q.add('tipe=${filter.category.slug}');
    if (filter.genre != null) q.add('genre=${Uri.encodeQueryComponent(filter.genre!.slug)}');
    if (filter.status != ComicStatusFilter.all) {
      q.add('status=${filter.status == ComicStatusFilter.ongoing ? 'ongoing' : 'end'}');
    }
    final qs = q.join('&');
    return _list([
      '$_api/manga/page/$page/?$qs',
      '$baseUrl/manga/page/$page/?$qs',
      '$baseUrl/pustaka/page/$page/?$qs',
    ], status: filter.status, category: filter.category);
  }

  List<ComicGenre>? _genres;

  @override
  Future<List<ComicGenre>> getGenres() async {
    if (_genres != null) return _genres!;
    for (final u in ['$baseUrl/pustaka/', '$baseUrl/manga/']) {
      try {
        final list = parseGenreOptions(parseHtml(await _http.getHtml(u)));
        if (list.length >= 5) return _genres = list;
      } catch (e) {
        logger.w('Genre Komiku $u gagal: $e');
      }
    }
    return kCommonGenres;
  }

  @override
  Future<List<Comic>> search(String query, {int page = 1}) {
    final q = Uri.encodeQueryComponent(query);
    final pg = page <= 1 ? '' : 'page/$page/';
    return _list([
      '$_api/$pg?post_type=manga&s=$q',
      '$baseUrl/$pg?post_type=manga&s=$q',
      '$baseUrl/$pg?s=$q',
    ], searchQuery: query, quietEmpty: page > 1);
  }

  @override
  Future<Comic> getDetail(Comic comic) async {
    final doc = parseHtml(await _http.getHtml(comic.url));

    final title = cleanText(doc.querySelector('#Judul h1 span[itemprop="name"], #Judul h1, h1')?.text);
    final cover = imgUrl(doc.querySelector('.ims img, #Informasi img'), baseUrl) ??
        metaContent(doc, 'og:image');
    final synopsis = cleanText(doc.querySelector('p.desc, #Sinopsis p, .desc')?.text);

    final info = <String, String>{};
    for (final row in doc.querySelectorAll('table.inftable tr, #Informasi tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length >= 2) applyInfoLine('${cells[0].text}: ${cells[1].text}', info);
    }

    final genres = uniqueTexts(doc, 'ul.genre li a, .genre a');

    var chapters = <ComicChapter>[];
    for (final row in doc.querySelectorAll('#Daftar_Chapter tr, #daftarChapter tr')) {
      final a = row.querySelector('td.judulseries a[href], a[href]');
      if (a == null) continue;
      final url = absoluteUrl(baseUrl, a.attributes['href']);
      final text = cleanText(a.text);
      final n = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text)?.group(1);
      chapters.add(ComicChapter(
        title: text,
        url: url,
        number: n,
        date: cleanText(row.querySelector('td.tanggalseries')?.text),
      ));
    }
    if (chapters.isEmpty) chapters = layeredChapters(doc, baseUrl, comic.slug);
    chapters = sortChapters(chapters);

    return comic.copyWith(
      title: title.isEmpty ? null : title,
      cover: cover,
      synopsis: synopsis.isEmpty ? null : synopsis,
      status: info['status'],
      type: info['type'],
      author: info['author'],
      genres: genres,
      chapters: chapters,
    );
  }

  @override
  Future<List<String>> getChapterPages(ComicChapter chapter) => pagesWithRenderFallback(
        url: chapter.url,
        base: baseUrl,
        plain: _http.getHtml,
        rendered: _http.getHtmlRendered,
        renderedImages: _http.getRenderedImages,
      );
}
