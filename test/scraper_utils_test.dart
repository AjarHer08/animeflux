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
}
