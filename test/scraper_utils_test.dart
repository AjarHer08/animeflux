import 'package:animeflux/core/constants.dart';
import 'package:animeflux/core/utils/html_utils.dart';
import 'package:animeflux/data/models/comic.dart';
import 'package:animeflux/data/scrapers/comic/comic_scraper.dart';
import 'package:animeflux/data/scrapers/scraper_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isDirectMediaUrl & tryBase64Decode', () {
    expect(isDirectMediaUrl('https://x.com/a/video.mp4?token=1'), isTrue);
    expect(isDirectMediaUrl('https://acefile.co/f/123'), isFalse);
    expect(tryBase64Decode('eyJpZCI6MX0='), '{"id":1}');
  });

  test('parseDownloadLinks membaca struktur .download li', () {
    final doc = parseHtml('''
<div class="download"><ul>
<li><strong>Mp4 360p</strong><a href="https://desudrive.com/x">Desudrive</a>
<a href="https://pixeldrain.com/u/abc">Pixeldrain</a></li>
</ul></div>''');
    final list = parseDownloadLinks(doc, 'https://otakudesu.blog');
    expect(list.length, 2);
    expect(list.first.quality, VideoQuality.q360);
    expect(list.first.host, 'desudrive');
  });

  test('parseComicLinks berbasis pola URL', () {
    final doc = parseHtml('''
<div><a href="https://v7.kiryuu.to/manga/dandadan/"><img src="https://v7.kiryuu.to/c.jpg"></a>
<h1><a href="https://v7.kiryuu.to/manga/dandadan/">DANDADAN</a></h1>
<a href="https://v7.kiryuu.to/manga/dandadan/chapter-252.837077/">Chapter 252</a></div>''');
    final comics = parseComicLinks(doc, 'https://v7.kiryuu.to', ComicSourceId.kiryuu);
    expect(comics.length, 1);
    expect(comics.first.title, 'DANDADAN');
    expect(comics.first.cover, 'https://v7.kiryuu.to/c.jpg');
  });

  test('parseChapterLinks', () {
    final doc = parseHtml('''
<a href="https://v7.kiryuu.to/manga/dandadan/chapter-252.837077/">Chapter 252 2 hours ago</a>
<a href="https://v7.kiryuu.to/manga/dandadan/chapter-251.831185/">Chapter 251 6 days ago</a>''');
    final ch = parseChapterLinks(doc, 'https://v7.kiryuu.to', onlyContaining: '/dandadan/');
    expect(ch.length, 2);
    expect(ch.first.number, '252');
  });

  test('extractPageImages dari ts_reader', () {
    const html = '''<script>ts_reader.run({"sources":[{"source":"S1","images":["https://cdn.x/1.jpg","https://cdn.x/2.jpg"]}]});</script>''';
    final pages = extractPageImages(parseHtml(html), html, 'https://komikstation.org');
    expect(pages, ['https://cdn.x/1.jpg', 'https://cdn.x/2.jpg']);
  });

  test('layeredChapters: slug halaman seri beda dengan slug URL chapter', () {
    final doc = parseHtml('''
<div class="listupd"><div class="bsx"><a href="https://k.org/lain-chapter-9/">Chapter 9</a></div></div>
<div class="bixbox"><a href="https://k.org/judul-asli-chapter-3/">Chapter 3</a>
<a href="https://k.org/judul-asli-chapter-2/">Chapter 2</a>
<a href="https://k.org/judul-asli-chapter-1/">Chapter 1</a></div>''');
    final ch = layeredChapters(doc, 'https://k.org', 'judul-asli-2');
    expect(ch.length, 3);
    expect(ch.first.number, '3');
  });

  test('layeredChapters: kontainer #chapterlist', () {
    final doc = parseHtml('''
<div id="chapterlist"><ul><li><a href="/x-chapter-10/">Chapter 10</a></li>
<li><a href="/x-chapter-9/">Chapter 9</a></li></ul></div>''');
    expect(layeredChapters(doc, 'https://k.org', 'x').length, 2);
  });

  test('filterRelevant membuang hasil yang tak terkait', () {
    Comic c(String t) => Comic(
        id: t, source: ComicSourceId.kiryuu, title: t, slug: t.toLowerCase().replaceAll(' ', '-'), url: 'u');
    final r = filterRelevant([c('Solo Leveling'), c('One Piece')], 'solo lev');
    expect(r.map((e) => e.title), ['Solo Leveling']);
  });

  test('parseGenreOptions membaca checkbox genre[]', () {
    final doc = parseHtml('''
<ul><li><input type="checkbox" id="g1" name="genre[]" value="action"><label for="g1">Action</label></li>
<li><input type="checkbox" id="g2" name="genre[]" value="school-life"><label for="g2">School Life</label></li></ul>''');
    final g = parseGenreOptions(doc);
    expect(g.map((e) => e.slug), ['action', 'school-life']);
  });
}
