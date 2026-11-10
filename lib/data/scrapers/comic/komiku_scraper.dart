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

  Future<List<Comic>> _list(List<String> urls) async {
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
            cover: imgUrl(card.querySelector('.bgei img, img'), baseUrl),
            type: cleanText(card.querySelector('.tpe1_inf b')?.text),
            latestChapter: cleanText(card.querySelector('.new1 a span:last-child, .new1')?.text),
          ));
        }
        if (out.isNotEmpty) return out;
        final generic = parseComicLinks(doc, baseUrl, source);
        if (generic.isNotEmpty) return generic;
      } catch (e) {
        lastError = e;
        logger.w('Komiku $u gagal: $e');
      }
    }
    if (lastError != null) throw lastError;
    return const [];
  }

  /// API Komiku: filter lewat `tipe=manga|manhwa|manhua`.
  String _tipe(ComicCategory c) => c == ComicCategory.all ? '' : '&tipe=${c.slug}';

  @override
  Future<List<Comic>> getLatest({int page = 1, ComicCategory category = ComicCategory.all}) => _list([
        '$_api/manga/page/$page/?orderby=modified${_tipe(category)}',
        '$baseUrl/manga/page/$page/?orderby=modified${_tipe(category)}',
      ]);

  @override
  Future<List<Comic>> getPopular({int page = 1, ComicCategory category = ComicCategory.all}) => _list([
        '$_api/manga/page/$page/?orderby=meta_value_num${_tipe(category)}',
        '$baseUrl/manga/page/$page/?orderby=meta_value_num${_tipe(category)}',
      ]);

  @override
  Future<List<Comic>> search(String query, {int page = 1}) {
    final q = Uri.encodeQueryComponent(query);
    return _list([
      '$_api/?post_type=manga&s=$q',
      '$baseUrl/?post_type=manga&s=$q',
    ]);
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
    if (chapters.isEmpty) {
      chapters = parseChapterLinks(doc, baseUrl, onlyContaining: comic.slug.split('-').first);
    }

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
  Future<List<String>> getChapterPages(ComicChapter chapter) async {
    final html = await _http.getHtml(chapter.url);
    return extractPageImages(parseHtml(html), html, baseUrl);
  }
}
