/// Kontrak + helper bersama scraper komik.
///
/// PENTING: struktur HTML situs bisa berubah kapan saja. Karena itu parser
/// memakai beberapa lapis: selector tema (MangaStream dsb.) lalu fallback
/// berbasis pola URL (`/manga/<slug>/`, `.../chapter-N`) yang jauh lebih
/// stabil daripada nama class CSS.
library;

import 'dart:convert';

import 'package:html/dom.dart' as dom;

import '../../../core/constants.dart';
import '../../../core/utils/html_utils.dart';
import '../../models/comic.dart';
import '../scraper_utils.dart';

abstract class ComicScraper {
  ComicSourceId get source;
  String get baseUrl => source.baseUrl;

  /// Header untuk memuat gambar (hotlink protection → wajib Referer).
  Map<String, String> get imageHeaders => {
        'Referer': '$baseUrl/',
        'User-Agent': kDesktopUserAgents[0],
      };

  Future<List<Comic>> getLatest({int page = 1, ComicCategory category = ComicCategory.all});
  Future<List<Comic>> getPopular({int page = 1, ComicCategory category = ComicCategory.all});
  Future<List<Comic>> search(String query, {int page = 1});
  Future<Comic> getDetail(Comic comic);
  Future<List<String>> getChapterPages(ComicChapter chapter);
}

// ------------------------------------------------------------------ helpers

String slugOf(String url) {
  final segs = <String>[];
  final raw = Uri.tryParse(url)?.pathSegments;
  if (raw != null) {
    for (final s in raw) {
      if (s.isNotEmpty) segs.add(s);
    }
  }
  return segs.isEmpty ? url : segs.last;
}

String titleFromSlug(String slug) {
  final words = <String>[];
  for (final w in slug.split('-')) {
    if (w.isEmpty) continue;
    words.add(w[0].toUpperCase() + w.substring(1));
  }
  return words.join(' ');
}

/// Teks unik & tidak kosong dari semua elemen yang cocok [selector].
/// Ditulis dengan loop eksplisit (tanpa rantai map/where) supaya tipe selalu String.
List<String> uniqueTexts(dom.Document doc, String selector) {
  final out = <String>[];
  for (final e in doc.querySelectorAll(selector)) {
    final t = cleanText(e.text);
    if (t.isNotEmpty && !out.contains(t)) out.add(t);
  }
  return out;
}

/// URL gambar dari <img> (menangani lazy-load & srcset).
String? imgUrl(dom.Element? img, String base) {
  if (img == null) return null;
  for (final attr in const ['data-src', 'data-lazy-src', 'data-original', 'src']) {
    final v = img.attributes[attr]?.trim();
    if (v != null && v.isNotEmpty && !v.startsWith('data:')) {
      return absoluteUrl(base, v);
    }
  }
  final srcset = img.attributes['srcset'] ?? img.attributes['data-srcset'];
  if (srcset != null && srcset.trim().isNotEmpty) {
    final first = srcset.split(',').first.trim().split(RegExp(r'\s+')).first;
    if (first.isNotEmpty && !first.startsWith('data:')) return absoluteUrl(base, first);
  }
  return null;
}

String? metaContent(dom.Document doc, String property) {
  final el = doc.querySelector('meta[property="$property"]') ??
      doc.querySelector('meta[name="$property"]');
  final v = el?.attributes['content'];
  return (v == null || v.trim().isEmpty) ? null : cleanText(v);
}

final RegExp _junkTitle = RegExp(
  r'^(chapter|ch\.?|ongoing|completed|tamat|manga|manhwa|manhua|mangatoon|hot|new|\d+(\.\d+)?)\b',
  caseSensitive: false,
);

class _Draft {
  final String slug;
  final String url;
  final dom.Element firstAnchor;
  String? title;
  String? cover;
  String? type;
  _Draft(this.slug, this.url, this.firstAnchor);
}

/// Parser kartu komik berbasis pola URL `/manga/<slug>/` (tema apa pun).
List<Comic> parseComicLinks(dom.Document doc, String base, ComicSourceId source) {
  final pathRe = RegExp(r'^/manga/([^/]+)/?$');
  final drafts = <String, _Draft>{};
  final baseHost = Uri.tryParse(base)?.host ?? '';

  for (final a in doc.querySelectorAll('a[href]')) {
    final abs = absoluteUrl(base, a.attributes['href']);
    final uri = Uri.tryParse(abs);
    if (uri == null || uri.host.isEmpty) continue;
    if (baseHost.isNotEmpty && uri.host != baseHost) continue;
    final m = pathRe.firstMatch(uri.path);
    if (m == null) continue;
    final slug = m.group(1)!;
    if (slug.endsWith('-novel')) continue; // daftar novel, bukan komik
    final url = '${uri.scheme}://${uri.host}/manga/$slug/';
    final d = drafts.putIfAbsent(slug, () => _Draft(slug, url, a));

    final img = a.querySelector('img');
    d.cover ??= imgUrl(img, base);

    String? cand = a.attributes['title']?.trim();
    if (cand == null || cand.isEmpty) {
      final h = a.querySelector('h1,h2,h3,h4,h5');
      cand = h == null ? null : cleanText(h.text);
    }
    if (cand == null || cand.isEmpty) {
      final alt = img?.attributes['alt']?.trim();
      if (alt != null && alt.isNotEmpty) cand = alt;
    }
    if (cand == null || cand.isEmpty) {
      final t = cleanText(a.text);
      if (t.isNotEmpty && t.length < 100 && !_junkTitle.hasMatch(t)) cand = t;
    }
    if ((d.title == null || d.title!.isEmpty) && cand != null && cand.isNotEmpty) {
      d.title = cleanText(cand);
    }
  }

  final out = <Comic>[];
  for (final d in drafts.values) {
    var cover = d.cover;
    if (cover == null) {
      dom.Element? p = d.firstAnchor.parent;
      for (var i = 0; i < 4 && p != null && cover == null; i++) {
        cover = imgUrl(p.querySelector('img'), base);
        p = p.parent;
      }
    }
    out.add(Comic(
      id: Comic.makeId(source, d.slug),
      source: source,
      title: (d.title == null || d.title!.isEmpty) ? titleFromSlug(d.slug) : d.title!,
      slug: d.slug,
      url: d.url,
      cover: cover,
    ));
  }
  return out;
}

/// Parser chapter berbasis pola URL (`...chapter...`).
List<ComicChapter> parseChapterLinks(dom.Document doc, String base, {String? onlyContaining}) {
  final out = <ComicChapter>[];
  final seen = <String>{};
  final baseHost = Uri.tryParse(base)?.host ?? '';
  for (final a in doc.querySelectorAll('a[href]')) {
    final href = a.attributes['href'] ?? '';
    if (!RegExp(r'chapter|-ch-|/ch-', caseSensitive: false).hasMatch(href)) continue;
    final abs = absoluteUrl(base, href);
    final uri = Uri.tryParse(abs);
    if (uri == null || (baseHost.isNotEmpty && uri.host != baseHost)) continue;
    if (onlyContaining != null && !abs.contains(onlyContaining)) continue;
    if (!seen.add(abs)) continue;
    final text = cleanText(a.text);
    final numMatch = RegExp(r'chapter[\s\-_.]*(\d+(?:[.\-]\d+)?)', caseSensitive: false)
            .firstMatch(text) ??
        RegExp(r'chapter-(\d+(?:[.\-]\d+)?)', caseSensitive: false).firstMatch(abs);
    final number = numMatch?.group(1)?.replaceAll('-', '.');
    final titleMatch = RegExp(r'^(Chapter|Ch\.?)\s*[\d.]+[^\d]*', caseSensitive: false).firstMatch(text);
    out.add(ComicChapter(
      title: text.isEmpty ? 'Chapter ${number ?? ''}'.trim() : (titleMatch?.group(0)?.trim() ?? text),
      url: abs,
      number: number,
      date: null,
    ));
  }
  return sortChapters(out);
}

/// Urutkan terbaru (nomor terbesar) dulu bila nomor tersedia.
List<ComicChapter> sortChapters(List<ComicChapter> list) {
  final withNum = list.where((c) => double.tryParse(c.number ?? '') != null).length;
  if (withNum < list.length * 0.8 || list.length < 2) return list;
  final sorted = List<ComicChapter>.of(list)
    ..sort((a, b) =>
        (double.tryParse(b.number ?? '') ?? 0).compareTo(double.tryParse(a.number ?? '') ?? 0));
  return sorted;
}

final RegExp _infoRe = RegExp(
  r'^(status|type|tipe|jenis|author|pengarang|penulis|artist|seniman|released|rilis|serialization)\s*[:：]?\s*(.+)$',
  caseSensitive: false,
);

/// Terapkan baris info "Status: Ongoing" ke map hasil.
void applyInfoLine(String line, Map<String, String> into) {
  final m = _infoRe.firstMatch(cleanText(line));
  if (m == null) return;
  final key = m.group(1)!.toLowerCase();
  final val = m.group(2)!.trim();
  if (val.isEmpty) return;
  if (key == 'status') into['status'] = val;
  if (key == 'type' || key == 'tipe' || key == 'jenis') into['type'] = val;
  if (key == 'author' || key == 'pengarang' || key == 'penulis') into['author'] = val;
}

/// Ekstrak URL halaman chapter dari DOM + JSON yang tertanam.
List<String> extractPageImages(dom.Document doc, String html, String base) {
  List<String> clean(Iterable<String> raw) {
    final out = <String>[];
    final seen = <String>{};
    final junk = RegExp(
      r'(logo|avatar|gravatar|/themes/|\.svg(\?|$)|histats|klikcdn|88cdn|emoji|loading|placeholder|/ads?[-_/])',
      caseSensitive: false,
    );
    for (final u in raw) {
      final url = u.trim();
      if (url.isEmpty || url.startsWith('data:')) continue;
      if (junk.hasMatch(url)) continue;
      if (seen.add(url)) out.add(url);
    }
    return out;
  }

  // 1) MangaStream: ts_reader.run({... "sources":[{"images":[...]}]})
  final ts = RegExp(r'ts_reader\.run\((\{.*?\})\s*\)\s*;', dotAll: true).firstMatch(html);
  if (ts != null) {
    try {
      final j = jsonDecode(ts.group(1)!) as Map<String, dynamic>;
      final sources = (j['sources'] as List?) ?? const [];
      if (sources.isNotEmpty) {
        final imgs = ((sources.first as Map)['images'] as List?)?.map((e) => '$e') ?? const <String>[];
        final r = clean(imgs.map((e) => absoluteUrl(base, e)));
        if (r.isNotEmpty) return r;
      }
    } catch (_) {}
  }

  // 2) Atribut JSON (tema baru): data-image-data='["url",...]'
  final fromAttr = <String>[];
  for (final el in doc.querySelectorAll('[data-image-data]')) {
    try {
      final j = jsonDecode(el.attributes['data-image-data'] ?? '[]');
      if (j is List) {
        for (final e in j) {
          if (e is String) fromAttr.add(absoluteUrl(base, e));
          if (e is Map && e['url'] != null) fromAttr.add(absoluteUrl(base, '${e['url']}'));
        }
      }
    } catch (_) {}
  }
  var r = clean(fromAttr);
  if (r.isNotEmpty) return r;

  // 3) Selector reader umum.
  const selectors = [
    '#readerarea img',
    '#Baca_Komik img',
    '.reading-content img',
    'section[data-image-data] img',
    '.chapter-images img',
    '#chapter-images img',
    '.reader-area img',
    '.reader img',
  ];
  for (final sel in selectors) {
    final urls = doc.querySelectorAll(sel).map((e) => imgUrl(e, base)).whereType<String>();
    r = clean(urls);
    if (r.isNotEmpty) return r;
  }

  // 4) Fallback: semua <img> berekstensi gambar di konten utama.
  final scope = doc.querySelector('main, article, #content, .content') ?? doc.body;
  final ext = RegExp(r'\.(jpe?g|png|webp|avif)(\?|$)', caseSensitive: false);
  final urls = (scope?.querySelectorAll('img') ?? const <dom.Element>[])
      .map((e) => imgUrl(e, base))
      .whereType<String>()
      .where((u) => ext.hasMatch(u));
  return clean(urls);
}
