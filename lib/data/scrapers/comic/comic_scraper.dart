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

  /// Daftar komik dengan filter lengkap (tipe, status, genre, urutan).
  Future<List<Comic>> browse({int page = 1, ComicFilter filter = const ComicFilter()});

  /// Urutan yang didukung sumber ini.
  List<ComicOrder> get supportedOrders => ComicOrder.values;

  /// Daftar genre sumber (diambil dari situs; jatuh ke daftar umum bila gagal).
  Future<List<ComicGenre>> getGenres();

  Future<List<Comic>> getLatest({int page = 1, ComicCategory category = ComicCategory.all}) =>
      browse(page: page, filter: ComicFilter(category: category, order: ComicOrder.latest));

  Future<List<Comic>> getPopular({int page = 1, ComicCategory category = ComicCategory.all}) =>
      browse(page: page, filter: ComicFilter(category: category, order: ComicOrder.popular));

  Future<List<Comic>> search(String query, {int page = 1});
  Future<Comic> getDetail(Comic comic);
  Future<List<String>> getChapterPages(ComicChapter chapter);
}

/// Genre umum — dipakai bila daftar genre situs gagal dibaca.
const List<ComicGenre> kCommonGenres = [
  ComicGenre('action', 'Action'),
  ComicGenre('adventure', 'Adventure'),
  ComicGenre('comedy', 'Comedy'),
  ComicGenre('cooking', 'Cooking'),
  ComicGenre('crime', 'Crime'),
  ComicGenre('drama', 'Drama'),
  ComicGenre('ecchi', 'Ecchi'),
  ComicGenre('fantasy', 'Fantasy'),
  ComicGenre('game', 'Game'),
  ComicGenre('gender-bender', 'Gender Bender'),
  ComicGenre('harem', 'Harem'),
  ComicGenre('historical', 'Historical'),
  ComicGenre('horror', 'Horror'),
  ComicGenre('isekai', 'Isekai'),
  ComicGenre('josei', 'Josei'),
  ComicGenre('magic', 'Magic'),
  ComicGenre('martial-arts', 'Martial Arts'),
  ComicGenre('mature', 'Mature'),
  ComicGenre('mecha', 'Mecha'),
  ComicGenre('military', 'Military'),
  ComicGenre('music', 'Music'),
  ComicGenre('mystery', 'Mystery'),
  ComicGenre('psychological', 'Psychological'),
  ComicGenre('reincarnation', 'Reincarnation'),
  ComicGenre('romance', 'Romance'),
  ComicGenre('school-life', 'School Life'),
  ComicGenre('sci-fi', 'Sci-Fi'),
  ComicGenre('seinen', 'Seinen'),
  ComicGenre('shoujo', 'Shoujo'),
  ComicGenre('shounen', 'Shounen'),
  ComicGenre('slice-of-life', 'Slice of Life'),
  ComicGenre('sports', 'Sports'),
  ComicGenre('supernatural', 'Supernatural'),
  ComicGenre('survival', 'Survival'),
  ComicGenre('thriller', 'Thriller'),
  ComicGenre('tragedy', 'Tragedy'),
  ComicGenre('webtoons', 'Webtoons'),
];

/// Ambil opsi genre dari form filter situs: checkbox/select bernama genre,
/// atau tautan `/genre/<slug>/`. Hasil unik, urut abjad.
List<ComicGenre> parseGenreOptions(dom.Document doc) {
  final out = <String, ComicGenre>{};
  void add(String? slug, String? label) {
    final s = (slug ?? '').trim().toLowerCase();
    var l = cleanText(label);
    l = l.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '').trim();
    if (s.isEmpty || l.isEmpty || l.length > 30) return;
    if (RegExp(r'^(all|semua|0)$').hasMatch(s) || RegExp(r'^(all|semua)\b', caseSensitive: false).hasMatch(l)) return;
    out.putIfAbsent(s, () => ComicGenre(s, l));
  }

  for (final el in doc.querySelectorAll('input[name^="genre"]')) {
    final v = el.attributes['value'];
    if (v == null || v.isEmpty) continue;
    String? label;
    final id = el.attributes['id'];
    if (id != null && id.isNotEmpty) {
      for (final lb in doc.querySelectorAll('label')) {
        if (lb.attributes['for'] == id) {
          label = lb.text;
          break;
        }
      }
    }
    label ??= el.parent?.text;
    add(v, label);
  }
  for (final o in doc.querySelectorAll('select[name^="genre"] option')) {
    add(o.attributes['value'], o.text);
  }
  if (out.isEmpty) {
    final re = RegExp(r'/genres?/([^/?#]+)/?');
    for (final a in doc.querySelectorAll('a[href]')) {
      final m = re.firstMatch(a.attributes['href'] ?? '');
      if (m != null) add(m.group(1), a.text);
    }
  }
  final list = out.values.toList()..sort((a, b) => a.label.compareTo(b.label));
  return list;
}

/// Saring hasil pencarian hasil parser generik (bisa memuat sidebar/komik
/// tidak terkait): sisakan yang judul/slug-nya memuat kata kunci.
List<Comic> filterRelevant(List<Comic> list, String query) {
  final tokens = <String>[];
  for (final t in query.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) {
    if (t.isNotEmpty) tokens.add(t);
  }
  if (tokens.isEmpty) return list;
  bool has(Comic c, String t) =>
      c.title.toLowerCase().contains(t) || c.slug.toLowerCase().contains(t);
  final all = [for (final c in list) if (tokens.every((t) => has(c, t))) c];
  if (all.isNotEmpty) return all;
  final strong = [for (final t in tokens) if (t.length >= 3) t];
  return [for (final c in list) if (strong.any((t) => has(c, t))) c];
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

final RegExp _placeholderImg = RegExp(
  r'(lazy|blank|placeholder|loading|spacer|pixel|transparent|default[-_]?(cover|thumb)|no[-_]?image|1x1)',
  caseSensitive: false,
);

String? _firstFromSrcset(String? srcset) {
  if (srcset == null || srcset.trim().isEmpty) return null;
  // Pilih kandidat dengan lebar terbesar (deskriptor "w"), kalau tidak ada ambil yang pertama.
  String? best;
  double bestW = -1;
  for (final part in srcset.split(RegExp(r',\s+|,(?=https?:)|,(?=/)'))) {
    final bits = part.trim().split(RegExp(r'\s+'));
    if (bits.isEmpty || bits.first.isEmpty || bits.first.startsWith('data:')) continue;
    final w = bits.length > 1 ? (double.tryParse(bits[1].replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0) : 0.0;
    if (best == null || w > bestW) {
      best = bits.first;
      bestW = w;
    }
  }
  return best;
}

String? _bgImage(dom.Element? el) {
  final st = el?.attributes['style'];
  if (st == null) return null;
  final m = RegExp(r'url\(\s*["' "'" r']?([^"' "'" r')]+)["' "'" r']?\s*\)').firstMatch(st);
  return m?.group(1);
}

/// URL gambar dari <img> (lazy-load, srcset, <picture>, background-image, noscript).
String? imgUrl(dom.Element? img, String base) {
  if (img == null) return null;
  String? ok(String? v, {bool checkPlaceholder = false}) {
    final t = v?.trim();
    if (t == null || t.isEmpty || t.startsWith('data:') || t == '#') return null;
    if (checkPlaceholder && _placeholderImg.hasMatch(t)) return null;
    final abs = absoluteUrl(base, t);
    return abs.isEmpty ? null : abs;
  }

  // Elemen bukan <img>: cari <img>/<source>/background di dalamnya.
  if (img.localName != 'img') {
    final inner = img.querySelector('img');
    if (inner != null) return imgUrl(inner, base);
    final fromSrc = ok(_firstFromSrcset(img.querySelector('source')?.attributes['srcset']));
    if (fromSrc != null) return fromSrc;
    return ok(_bgImage(img));
  }

  for (final attr in const [
    'data-src',
    'data-lazy-src',
    'data-original',
    'data-cfsrc',
    'data-lazyload',
    'data-wpfc-original-src',
    'data-img',
    'data-thumb',
  ]) {
    final r = ok(img.attributes[attr]);
    if (r != null) return r;
  }
  final fromSet = ok(_firstFromSrcset(img.attributes['data-srcset'] ?? img.attributes['srcset']));
  if (fromSet != null) return fromSet;
  final direct = ok(img.attributes['src'], checkPlaceholder: true);
  if (direct != null) return direct;
  final pic = img.parent;
  if (pic != null && pic.localName == 'picture') {
    final s = ok(_firstFromSrcset(pic.querySelector('source')?.attributes['srcset']));
    if (s != null) return s;
  }
  final ns = img.parent?.querySelector('noscript');
  if (ns != null) {
    final m = RegExp(r'src=["' "'" r']([^"' "'" r']+)["' "'" r']').firstMatch(ns.text);
    final r = ok(m?.group(1));
    if (r != null) return r;
  }
  return ok(img.attributes['src']);
}

/// Gambar bendera / ikon tipe di dalam kartu komik. Tema MangaStream
/// menaruhnya SEBELUM cover asli, jadi kalau tidak difilter, thumbnail yang
/// tampil adalah bendera Korea/China/Jepang.
final RegExp _flagImg = RegExp(
  r'(/flags?/|flag[-_]?(kr|cn|jp|id|ko|zh|ja)\b|bendera|country[-_]?(flag|icon))',
  caseSensitive: false,
);

String? _coverCandidate(dom.Element el, String base) {
  final url = imgUrl(el, base);
  if (url == null) return null;
  if (_flagImg.hasMatch(url)) return null;
  if (_flagImg.hasMatch(el.attributes['alt'] ?? '')) return null;
  if (_flagImg.hasMatch(el.attributes['class'] ?? '')) return null;
  return url;
}

/// Apakah elemen ini penanda cover utama (bukan thumbnail/ikon).
bool _isMainCover(dom.Element el) {
  final cls = el.attributes['class'] ?? '';
  return cls.contains('ts-post-image') ||
      cls.contains('wp-post-image') ||
      (el.attributes['itemprop'] ?? '') == 'image';
}

/// Cari cover di dalam sebuah kartu: <img>, <picture>, atau background-image.
/// Bendera/ikon tipe dilewati; cover utama (ts-post-image) diprioritaskan.
String? coverIn(dom.Element? card, String base) {
  if (card == null) return null;

  String? fallback;
  for (final img in card.querySelectorAll('img')) {
    final u = _coverCandidate(img, base);
    if (u == null) continue;
    if (_isMainCover(img)) return u;
    fallback ??= u;
  }
  if (fallback != null) return fallback;

  for (final e in card.querySelectorAll('[style*="url("]')) {
    final b = _coverCandidate(e, base);
    if (b != null) return b;
  }
  return null;
}

final RegExp _typeWord = RegExp(r'\b(manga|manhwa|manhua)\b', caseSensitive: false);

String? _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

/// Tipe komik dari kartu daftar (badge "Manga"/"Manhwa"/"Manhua").
String? typeFromElement(dom.Element? card) {
  if (card == null) return null;
  final cls = _typeWord.firstMatch(card.attributes['class'] ?? '');
  if (cls != null) return _cap(cls.group(1)!);
  for (final el in card.querySelectorAll('span, div, b, a, strong')) {
    final t = cleanText(el.text);
    if (t.isEmpty || t.length > 12) continue;
    final m = _typeWord.firstMatch(t);
    if (m == null) continue;
    if (t.toLowerCase() == m.group(1)!.toLowerCase()) return _cap(m.group(1)!);
  }
  // Tema Kiryuu memakai ikon SVG: .../static/svg/manhwa.svg alt="manhwa".
  for (final img in card.querySelectorAll('img')) {
    final alt = (img.attributes['alt'] ?? '').trim();
    final mAlt = RegExp(r'^(manga|manhwa|manhua)$', caseSensitive: false).firstMatch(alt);
    if (mAlt != null) return _cap(mAlt.group(1)!);
    final src = img.attributes['src'] ?? img.attributes['data-src'] ?? '';
    if (!src.contains('/svg/') && !src.contains('type')) continue;
    final m = _typeWord.firstMatch(src);
    if (m != null) return _cap(m.group(1)!);
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
    d.cover ??= coverIn(a, base);

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
      d.title = cleanTitle(cand);
    }
    d.type ??= typeFromElement(a) ?? typeFromElement(a.parent);
  }

  final out = <Comic>[];
  for (final d in drafts.values) {
    var cover = d.cover;
    if (cover == null) {
      dom.Element? p = d.firstAnchor.parent;
      for (var i = 0; i < 4 && p != null && cover == null; i++) {
        cover = coverIn(p, base);
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
      type: d.type,
    ));
  }
  return out;
}

final RegExp _chapHref =
    RegExp(r'chapter|-ch-|/ch-|/ch/|-bab-|/bab-|/episode-\d', caseSensitive: false);

final RegExp _noiseClass = RegExp(
  r'(listupd|widget|sidebar|related|popular|serieslist|utao|bsx|rekomendasi|recommend|footer|latest-?(update|post))',
  caseSensitive: false,
);

/// Apakah elemen berada di blok non-konten (sidebar, rekomendasi, daftar update).
bool _inNoise(dom.Element el) {
  dom.Element? p = el;
  for (var i = 0; i < 8 && p != null; i++) {
    final cls = '${p.attributes['class'] ?? ''} ${p.attributes['id'] ?? ''}';
    if (cls.trim().isNotEmpty && _noiseClass.hasMatch(cls)) return true;
    p = p.parent;
  }
  return false;
}

List<ComicChapter> chaptersFromAnchors(
  Iterable<dom.Element> anchors,
  String base, {
  bool Function(String abs)? accept,
}) {
  final out = <ComicChapter>[];
  final seen = <String>{};
  final baseHost = Uri.tryParse(base)?.host ?? '';
  for (final a in anchors) {
    final href = a.attributes['href'] ?? '';
    if (href.isEmpty || href.startsWith('#') || !_chapHref.hasMatch(href)) continue;
    final abs = absoluteUrl(base, href);
    final uri = Uri.tryParse(abs);
    if (uri == null || (baseHost.isNotEmpty && uri.host != baseHost)) continue;
    if (accept != null && !accept(abs)) continue;
    if (!seen.add(abs)) continue;
    final text = cleanText(a.text);
    final numMatch = RegExp(r'(?:chapter|ch|bab|episode)[\s\-_.]*(\d+(?:[.\-]\d+)?)', caseSensitive: false)
            .firstMatch(text) ??
        RegExp(r'(?:chapter|ch|bab|episode)-(\d+(?:[.\-]\d+)?)', caseSensitive: false).firstMatch(abs);
    final number = numMatch?.group(1)?.replaceAll('-', '.');
    final titleMatch = RegExp(r'^(Chapter|Ch\.?|Bab|Episode)\s*[\d.]+[^\d]*', caseSensitive: false).firstMatch(text);
    out.add(ComicChapter(
      title: text.isEmpty ? 'Chapter ${number ?? ''}'.trim() : (titleMatch?.group(0)?.trim() ?? text),
      url: abs,
      number: number,
      date: null,
    ));
  }
  return out;
}

/// Parser chapter berbasis pola URL (`...chapter...`).
List<ComicChapter> parseChapterLinks(dom.Document doc, String base, {String? onlyContaining}) {
  return sortChapters(chaptersFromAnchors(
    doc.querySelectorAll('a[href]'),
    base,
    accept: onlyContaining == null ? null : (abs) => abs.contains(onlyContaining),
  ));
}

/// Kunci "seri" sebuah URL chapter: URL tanpa bagian chapter-nya.
String _seriesKey(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  return path
      .replaceAll(RegExp(r'[-/]?(chapter|ch|bab|episode)[-_.]?\d[^/]*/?$', caseSensitive: false), '')
      .toLowerCase();
}

/// Cari daftar chapter dari halaman detail dengan beberapa lapis strategi,
/// tanpa bergantung pada nama class tema:
///  1) tautan chapter di dalam kontainer daftar chapter yang dikenal,
///  2) semua tautan chapter di luar sidebar/rekomendasi yang memuat slug seri,
///  3) kelompok tautan chapter terbesar yang berbagi prefix URL yang sama
///     (slug seri di URL chapter bisa berbeda dari slug halaman seri).
List<ComicChapter> layeredChapters(dom.Document doc, String base, String slug) {
  const containers =
      '#chapterlist, .eplister, .bxcl, .clstyle, .chapter-list, #Daftar_Chapter, #daftarChapter, '
      '.listing-chapters_wrap, .chapters, .chapter_list, [id*="chapter"][id*="list"], [class*="chapter-list"]';
  final inBox = <dom.Element>[];
  for (final box in doc.querySelectorAll(containers)) {
    inBox.addAll(box.querySelectorAll('a[href]'));
  }
  var r = chaptersFromAnchors(inBox, base);
  if (r.isNotEmpty) return sortChapters(r);

  final loose = [for (final a in doc.querySelectorAll('a[href]')) if (!_inNoise(a)) a];

  if (slug.isNotEmpty) {
    r = chaptersFromAnchors(loose, base, accept: (abs) => abs.contains(slug));
    if (r.isNotEmpty) return sortChapters(r);
    // slug sering berakhiran angka/"-id"; coba inti slug (maks 3 kata pertama).
    final core = slug.split('-').where((w) => w.isNotEmpty).take(3).join('-');
    if (core.length >= 4) {
      r = chaptersFromAnchors(loose, base, accept: (abs) => abs.contains(core));
      if (r.isNotEmpty) return sortChapters(r);
    }
  }

  final all = chaptersFromAnchors(loose, base);
  if (all.isEmpty) return const [];
  final groups = <String, List<ComicChapter>>{};
  for (final c in all) {
    groups.putIfAbsent(_seriesKey(c.url), () => []).add(c);
  }
  List<ComicChapter> best = const [];
  for (final g in groups.values) {
    if (g.length > best.length) best = g;
  }
  return sortChapters(best);
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

  // 2b) JSON gambar di <script> mana pun: "images":["...","..."] (ambil yang terpanjang).
  List<String> bestJson = const [];
  for (final m in RegExp(r'"images"\s*:\s*(\[[^\]]*\])').allMatches(html)) {
    try {
      final j = jsonDecode(m.group(1)!);
      if (j is! List) continue;
      final urls = <String>[];
      for (final e in j) {
        if (e is String) urls.add(absoluteUrl(base, e.replaceAll(r'\/', '/')));
        if (e is Map && e['url'] != null) urls.add(absoluteUrl(base, '${e['url']}'));
      }
      final c = clean(urls);
      if (c.length > bestJson.length) bestJson = c;
    } catch (_) {}
  }
  if (bestJson.length >= 2) return bestJson;

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

  // 4) Fallback: <img> berekstensi gambar di konten utama, TANPA sidebar /
  //    rekomendasi / sampul / thumbnail. (Dulu semua <img> ikut terambil, sehingga
  //    saat halaman chapter dimuat lewat JS yang tampil hanya sampul seri lain.)
  final scope = doc.querySelector('main, article, #content, .content') ?? doc.body;
  final ext = RegExp(r'\.(jpe?g|png|webp|avif)(\?|$)', caseSensitive: false);
  final urls = <String>[];
  for (final e in scope?.querySelectorAll('img') ?? const <dom.Element>[]) {
    if (_inNoise(e)) continue;
    final u = imgUrl(e, base);
    if (u == null || !ext.hasMatch(u) || isCoverLike(u)) continue;
    urls.add(u);
  }
  return clean(urls);
}

/// URL yang tampak seperti sampul / thumbnail seri (bukan halaman chapter).
bool isCoverLike(String url) => RegExp(
      r'(cover|thumb|poster|banner|sampul|/covers?/|-\d{2,4}x\d{2,4}\.(jpe?g|png|webp)|[?&]w=\d{2,3}(&|$))',
      caseSensitive: false,
    ).hasMatch(url);

/// Ambil gambar halaman chapter: HTML biasa dulu; kalau hasilnya kurang dari
/// 3 gambar (halaman dimuat lewat JS) ulangi dengan HTML hasil render WebView.
Future<List<String>> pagesWithRenderFallback({
  required String url,
  required String base,
  required Future<String> Function(String url) plain,
  required Future<String> Function(String url) rendered,
  Future<List<String>> Function(String url)? renderedImages,
  List<String> Function(String html)? extra,
}) async {
  List<String> run(String html) {
    var r = extractPageImages(parseHtml(html), html, base);
    if (r.length < 3 && extra != null) {
      final more = extra(html);
      if (more.length > r.length) r = more;
    }
    return r;
  }

  var pages = <String>[];
  try {
    pages = run(await plain(url));
  } catch (_) {}
  if (pages.length >= 3) return pages;
  try {
    final more = run(await rendered(url));
    if (more.length > pages.length) pages = more;
  } catch (_) {}
  if (pages.length >= 3 || renderedImages == null) return pages;
  // Terakhir: baca gambar langsung dari DOM hidup (gulir + pilih kontainer pembaca).
  try {
    final live = await renderedImages(url);
    if (live.length > pages.length) pages = live;
  } catch (_) {}
  return pages;
}
