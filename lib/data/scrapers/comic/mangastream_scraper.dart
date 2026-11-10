/// Scraper Komikstation (tema WordPress "MangaStream").
/// URL terverifikasi dari situs: seri `/manga/<slug>/`, chapter
/// `/<slug>-chapter-N/`, daftar `/manga/?order=update|popular&page=N`.
library;

import '../../../core/utils/html_utils.dart';
import '../../../core/utils/http_client.dart';
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
  Future<List<Comic>> getLatest({int page = 1, ComicCategory category = ComicCategory.all}) =>
      _list('$baseUrl/manga/?${_typeParam(category)}order=update&page=$page');

  @override
  Future<List<Comic>> getPopular({int page = 1, ComicCategory category = ComicCategory.all}) =>
      _list('$baseUrl/manga/?${_typeParam(category)}order=popular&page=$page');

  /// Tema MangaStream: filter tipe lewat `type=manga|manhwa|manhua`.
  String _typeParam(ComicCategory c) => c == ComicCategory.all ? '' : 'type=${c.slug}&';

  @override
  Future<List<Comic>> search(String query, {int page = 1}) {
    final q = Uri.encodeQueryComponent(query);
    return _list(page <= 1 ? '$baseUrl/?s=$q' : '$baseUrl/page/$page/?s=$q');
  }

  Future<List<Comic>> _list(String url) async {
    final doc = parseHtml(await _http.getHtml(url));
    final out = <Comic>[];
    final seen = <String>{};
    for (final card in doc.querySelectorAll('.listupd .bsx, .bs .bsx, .utao .uta')) {
      final a = card.querySelector('a[href]');
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
        cover: imgUrl(card.querySelector('img'), baseUrl),
        latestChapter: cleanText(card.querySelector('.epxs')?.text),
        rating: double.tryParse(cleanText(card.querySelector('.numscore')?.text)),
        type: cleanText(card.querySelector('.type')?.text),
      ));
    }
    if (out.isNotEmpty) return out;
    return parseComicLinks(doc, baseUrl, source);
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

    var chapters = <ComicChapter>[];
    for (final li in doc.querySelectorAll('#chapterlist li, .eplister li')) {
      final a = li.querySelector('a[href]');
      if (a == null) continue;
      final url = absoluteUrl(baseUrl, a.attributes['href']);
      final text = cleanText(li.querySelector('.chapternum, .epl-num')?.text ?? a.text);
      final n = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text)?.group(1) ??
          RegExp(r'chapter-(\d+(?:-\d+)?)').firstMatch(url)?.group(1)?.replaceAll('-', '.');
      chapters.add(ComicChapter(
        title: text.isEmpty ? 'Chapter ${n ?? ''}' : text,
        url: url,
        number: n,
        date: cleanText(li.querySelector('.chapterdate, .epl-date')?.text),
      ));
    }
    if (chapters.isEmpty) {
      chapters = parseChapterLinks(doc, baseUrl, onlyContaining: comic.slug);
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

  @override
  Future<List<String>> getChapterPages(ComicChapter chapter) async {
    final html = await _http.getHtml(chapter.url);
    return extractPageImages(parseHtml(html), html, baseUrl);
  }
}
