/// Scraper Komikstation (tema WordPress "MangaStream").
/// URL terverifikasi dari situs: seri `/manga/<slug>/`, chapter
/// `/<slug>-chapter-N/`, daftar `/manga/?order=update|popular&page=N`.
library;

import '../../../core/utils/html_utils.dart';
import 'package:html/dom.dart' as dom;

import '../../../core/utils/http_client.dart';
import '../../../core/utils/logger.dart';
import '../../models/comic.dart';
import '../scraper_utils.dart';
import 'comic_scraper.dart';

class MangaStreamScraper extends ComicScraper {
  MangaStreamScraper([ComicSourceId id = ComicSourceId.komikstation]) : _id = id;
  final ComicSourceId _id;
  final _http = HttpClient.instance;

  @override
  ComicSourceId get source => _id;

  @override
  List<ComicOrder> get supportedOrders => const [
        ComicOrder.latest,
        ComicOrder.popular,
        ComicOrder.az,
        ComicOrder.added,
      ];

  String _order(ComicOrder o) {
    switch (o) {
      case ComicOrder.latest:
        return 'update';
      case ComicOrder.popular:
        return 'popular';
      case ComicOrder.az:
        return 'title';
      case ComicOrder.added:
        return 'latest';
    }
  }

  /// Tema MangaStream: `/manga/?genre[]=x&status=ongoing&type=manhwa&order=update&page=N`.
  @override
  Future<List<Comic>> browse({int page = 1, ComicFilter filter = const ComicFilter()}) {
    final q = <String>[];
    if (filter.genre != null) q.add('genre%5B%5D=${Uri.encodeQueryComponent(filter.genre!.slug)}');
    if (filter.status != ComicStatusFilter.all) {
      q.add('status=${filter.status == ComicStatusFilter.ongoing ? 'ongoing' : 'completed'}');
    }
    if (filter.category != ComicCategory.all) q.add('type=${filter.category.slug}');
    q.add('order=${_order(filter.order)}');
    q.add('page=$page');
    return _list('$baseUrl/manga/?${q.join('&')}');
  }

  List<ComicGenre>? _genres;

  @override
  Future<List<ComicGenre>> getGenres() async {
    if (_genres != null) return _genres!;
    try {
      final list = parseGenreOptions(parseHtml(await _http.getHtml('$baseUrl/manga/')));
      if (list.length >= 5) return _genres = list;
    } catch (e) {
      logger.w('Genre ${source.label} gagal: $e');
    }
    return kCommonGenres;
  }

  @override
  Future<List<Comic>> search(String query, {int page = 1}) async {
    final q = Uri.encodeQueryComponent(query);
    final urls = [
      page <= 1 ? '$baseUrl/?s=$q' : '$baseUrl/page/$page/?s=$q',
      // Cadangan: daftar seri dengan parameter pencarian (hasil sama, template beda).
      '$baseUrl/manga/?title=$q&page=$page',
    ];
    Object? lastError;
    for (final u in urls) {
      try {
        final list = await _list(u, searchQuery: query);
        if (list.isNotEmpty) return list;
      } catch (e) {
        lastError = e;
        logger.w('Cari ${source.label} $u gagal: $e');
      }
    }
    // Halaman > 1 yang kosong/404 berarti memang habis, bukan error.
    if (lastError != null && page <= 1) throw lastError;
    return const [];
  }

  Future<List<Comic>> _list(String url, {String? searchQuery}) async {
    final doc = parseHtml(await _http.getHtml(url));
    final out = <Comic>[];
    final seen = <String>{};
    for (final card in doc.querySelectorAll('.listupd .bsx, .bs .bsx, .utao .uta, .listupd .bs')) {
      // Utamakan tautan ke halaman seri (/manga/...), bukan tautan chapter terbaru.
      dom.Element? a;
      for (final cand in card.querySelectorAll('a[href]')) {
        if ((cand.attributes['href'] ?? '').contains('/manga/')) {
          a = cand;
          break;
        }
      }
      a ??= card.querySelector('a[href]');
      final href = a?.attributes['href'];
      if (a == null || href == null) continue;
      final abs = absoluteUrl(baseUrl, href);
      final slug = slugOf(abs);
      if (!seen.add(slug)) continue;
      final title = cleanText(a.attributes['title'] ?? card.querySelector('.tt, h2, h3')?.text);
      out.add(Comic(
        id: Comic.makeId(source, slug),
        source: source,
        title: title.isEmpty ? titleFromSlug(slug) : title,
        slug: slug,
        url: abs,
        cover: coverIn(card, baseUrl),
        latestChapter: cleanText(card.querySelector('.epxs')?.text),
        rating: double.tryParse(cleanText(card.querySelector('.numscore')?.text)),
        type: cleanText(card.querySelector('.type')?.text),
      ));
    }
    if (out.isNotEmpty) return out;
    final generic = parseComicLinks(doc, baseUrl, source);
    return searchQuery == null ? generic : filterRelevant(generic, searchQuery);
  }

  @override
  Future<Comic> getDetail(Comic comic) async {
    final html = await _http.getHtml(comic.url);
    final doc = parseHtml(html);

    final title = cleanText(doc.querySelector('h1.entry-title, h1')?.text);
    final cover = imgUrl(doc.querySelector('.thumb img, .infomanga .thumb img'), baseUrl) ??
        metaContent(doc, 'og:image');
    final synopsis = cleanText(doc
        .querySelector('.entry-content[itemprop="description"], .entry-content-single, [itemprop="description"]')
        ?.text);

    final info = <String, String>{};
    for (final el in doc.querySelectorAll('.tsinfo .imptdt, .spe span, .fmed')) {
      applyInfoLine(el.text, info);
    }
    for (final row in doc.querySelectorAll('.infotable tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length >= 2) applyInfoLine('${cells[0].text}: ${cells[1].text}', info);
    }

    final genres = uniqueTexts(doc, '.mgen a, .seriestugenre a, .genres a');

    var chapters = _chaptersOf(doc, comic);
    if (chapters.isEmpty) {
      // Daftar chapter kadang dimuat JS / halaman terpotong: coba hasil render WebView.
      try {
        final rendered = parseHtml(await _http.getHtmlRendered(comic.url));
        chapters = _chaptersOf(rendered, comic);
      } catch (e) {
        logger.w('Chapter ${comic.slug} via WebView gagal: $e');
      }
    }
    if (chapters.isEmpty) chapters = await _ajaxChapters(comic);
    if (chapters.isEmpty) {
      // Pegangan terakhir: tombol "Chapter pertama / terbaru".
      chapters = sortChapters(chaptersFromAnchors(doc.querySelectorAll('.lastend a, .inepcx a'), baseUrl));
    }

    return comic.copyWith(
      title: title.isEmpty ? null : title,
      cover: cover,
      synopsis: synopsis.isEmpty ? null : synopsis,
      status: info['status'],
      type: info['type'],
      author: info['author'],
      rating: double.tryParse(cleanText(doc.querySelector('.num[itemprop="ratingValue"], .rating .num')?.text)),
      genres: genres,
      chapters: chapters,
    );
  }

  List<ComicChapter> _chaptersOf(dom.Document doc, Comic comic) {
    final out = <ComicChapter>[];
    final seen = <String>{};
    for (final li in doc.querySelectorAll(
        '#chapterlist li, .eplister li, .bxcl li, .clstyle li, ul.chapter-list li, .chapter-list li')) {
      final a = li.querySelector('a[href]');
      if (a == null) continue;
      final url = absoluteUrl(baseUrl, a.attributes['href']);
      if (!seen.add(url)) continue;
      final text = cleanText(li.querySelector('.chapternum, .epl-num')?.text ?? a.text);
      final n = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text)?.group(1) ??
          RegExp(r'chapter-(\d+(?:-\d+)?)').firstMatch(url)?.group(1)?.replaceAll('-', '.');
      out.add(ComicChapter(
        title: text.isEmpty ? 'Chapter ${n ?? ''}' : text,
        url: url,
        number: n,
        date: cleanText(li.querySelector('.chapterdate, .epl-date')?.text),
      ));
    }
    if (out.isNotEmpty) return sortChapters(out);
    return layeredChapters(doc, baseUrl, comic.slug);
  }

  /// Tema bergaya Madara memuat chapter lewat POST `<url>ajax/chapters/`.
  Future<List<ComicChapter>> _ajaxChapters(Comic comic) async {
    try {
      final base = comic.url.endsWith('/') ? comic.url : '${comic.url}/';
      final html = await _http.postForm('${base}ajax/chapters/', const {},
          headers: {'Referer': comic.url});
      return layeredChapters(parseHtml(html), baseUrl, comic.slug);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<String>> getChapterPages(ComicChapter chapter) async {
    final html = await _http.getHtml(chapter.url);
    return extractPageImages(parseHtml(html), html, baseUrl);
  }
}
