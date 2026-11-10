/// Helper bersama untuk semua scraper anime.
library;

import 'dart:convert';

import 'package:html/dom.dart' as dom;

import '../../core/constants.dart';
import '../../core/utils/html_utils.dart';
import '../../core/utils/http_client.dart';
import '../../core/utils/logger.dart';
import '../models/anime.dart';
import '../models/episode.dart';

/// Pola host -> nama server. Urutan penting (yang spesifik di atas).
const List<List<String>> _knownHosts = [
  ['acefile', 'acefile'],
  ['hxfile', 'hxfile'],
  ['mp4upload', 'mp4upload'],
  ['drive.google', 'gdrive'],
  ['gdrive', 'gdrive'],
  ['mega.nz', 'mega'],
  ['pixeldrain', 'pixeldrain'],
  ['krakenfiles', 'krakenfiles'],
  ['files.fm', 'filesfm'],
  ['zippyshare', 'zippyshare'],
  ['1fichier', '1fichier'],
  ['desudrive', 'desudrive'],
  ['odfiles', 'odfiles'],
  ['odstream', 'odstream'],
  ['racaty', 'racaty'],
  ['mediafire', 'mediafire'],
  ['terabox', 'terabox'],
  ['uptobox', 'uptobox'],
  ['yourupload', 'yourupload'],
  ['streamtape', 'streamtape'],
  ['doodstream', 'doodstream'],
  ['dood.', 'doodstream'],
  ['filedon', 'filedon'],
  ['mixdrop', 'mixdrop'],
  ['vidhide', 'vidhide'],
  ['mir.', 'mir'],
];

/// Deteksi nama server dari URL. Return `other` jika tidak dikenal.
String detectServer(String url) {
  final u = url.toLowerCase();
  for (final entry in _knownHosts) {
    if (u.contains(entry[0])) return entry[1];
  }
  return 'other';
}

/// True kalau URL menunjuk langsung ke file media (bisa diputar/diunduh
/// tanpa melewati halaman perantara).
bool isDirectMediaUrl(String url) {
  final path = url.split('#').first;
  return RegExp(r'\.(mp4|mkv|webm|m3u8|mov|avi)(\?|$)', caseSensitive: false)
      .hasMatch(path);
}

/// Decode base64 (standar/URL-safe, dengan/tanpa padding) ke string UTF-8.
String? tryBase64Decode(String? input) {
  if (input == null || input.isEmpty) return null;
  try {
    final normalized = base64.normalize(
      input.trim().replaceAll('-', '+').replaceAll('_', '/'),
    );
    return utf8.decode(base64.decode(normalized), allowMalformed: true);
  } catch (_) {
    return null;
  }
}

/// Jadikan URL absolut (menangani `//cdn...` dan path relatif).
String absoluteUrl(String base, String? url) {
  if (url == null || url.trim().isEmpty) return '';
  final u = url.trim();
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  if (u.startsWith('//')) return 'https:$u';
  return resolveUrl(base, u);
}

/// Ambil `src` iframe pertama yang valid (default player sebuah halaman).
String? firstIframeSrc(dom.Document doc, String base) {
  for (final f in doc.querySelectorAll('iframe')) {
    final raw = f.attributes['src'] ??
        f.attributes['data-src'] ??
        f.attributes['data-lazy-src'] ??
        '';
    if (raw.isEmpty || raw.startsWith('about:') || raw.startsWith('javascript:')) {
      continue;
    }
    final abs = absoluteUrl(base, raw);
    if (abs.isNotEmpty) return abs;
  }
  return null;
}

/// Cari URL iframe di dalam potongan HTML (hasil decode AJAX / base64).
String? iframeFromHtmlString(String html, String base) {
  final doc = parseHtml(html);
  return firstIframeSrc(doc, base);
}

/// Parse link download dari halaman episode.
///
/// Strategi: (1) container umum `.download`, `#download`, dst. dengan baris
/// `li`/`tr` — label resolusi diambil dari `strong`/`b`/`h4`; (2) fallback:
/// semua link ke host file yang dikenal.
List<DownloadOption> parseDownloadLinks(dom.Document doc, String base) {
  final result = <DownloadOption>[];
  final seen = <String>{};

  void add(String? href, String resLabel, String linkText) {
    if (href == null) return;
    final h = href.trim();
    if (h.isEmpty || h == '#' || h.startsWith('javascript:')) return;
    final url = absoluteUrl(base, h);
    if (url.isEmpty || !seen.add(url)) return;
    final host = detectServer(url);
    final label = resLabel.isNotEmpty
        ? (linkText.isNotEmpty ? '$resLabel • $linkText' : resLabel)
        : (linkText.isNotEmpty ? linkText : host);
    result.add(DownloadOption(
      label: label,
      quality: VideoQuality.fromLabel(resLabel) ?? VideoQuality.fromLabel(linkText),
      url: url,
      host: host != 'other' ? host : (linkText.isNotEmpty ? linkText.toLowerCase() : null),
    ));
  }

  const containers = '.download, #download, .dl-box, .download-eps, .dlbox, '
      '.soraddl, .soraurlx, .download-link, .dlx, .batchlink, '
      '.download-720p, .download-1080p, .download-480p, .download-360p, .download-hevc';
  for (final box in doc.querySelectorAll(containers)) {
    final rows = box.querySelectorAll('li, tr');
    if (rows.isEmpty) {
      final res = cleanText(box.querySelector('strong, b, h4, h3')?.text);
      for (final a in box.querySelectorAll('a[href]')) {
        add(a.attributes['href'], res, cleanText(a.text));
      }
      continue;
    }
    for (final row in rows) {
      // Baris yang membungkus baris lain (nested) dilewati agar tidak dobel.
      if (row.querySelector('li, tr') != null) continue;
      var res = cleanText(row.querySelector('strong, b, h4, h5, th')?.text);
      if (res.isEmpty) {
        final cells = row.querySelectorAll('td');
        if (cells.length > 1) res = cleanText(cells.first.text);
      }
      for (final a in row.querySelectorAll('a[href]')) {
        add(a.attributes['href'], res, cleanText(a.text));
      }
    }
  }

  if (result.isEmpty) {
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      if (detectServer(href) == 'other') continue;
      add(href, '', cleanText(a.text));
    }
  }
  return result;
}

/// Coba ambil URL video langsung (mp4/m3u8/webm) dari halaman embed.
Future<String?> resolveDirectFromEmbed(String embedUrl) async {
  if (embedUrl.isEmpty) return null;
  if (isDirectMediaUrl(embedUrl)) return embedUrl;
  try {
    final origin = Uri.parse(embedUrl).origin;
    final html = await HttpClient.instance.getHtml(
      embedUrl,
      extraHeaders: {'Referer': '$origin/'},
    );
    final cleaned = html.replaceAll(r'\/', '/').replaceAll('&amp;', '&');
    final doc = parseHtml(cleaned);

    final tagSrc = doc.querySelector('video source')?.attributes['src'] ??
        doc.querySelector('video')?.attributes['src'];
    if (tagSrc != null && tagSrc.isNotEmpty && !tagSrc.startsWith('blob:')) {
      return absoluteUrl(embedUrl, tagSrc);
    }

    final patterns = <RegExp>[
      RegExp(r'''(?:file|src|source|url)\s*[:=]\s*["']([^"']+\.(?:mp4|m3u8|webm|mkv)[^"']*)["']''',
          caseSensitive: false),
      RegExp(r'''(https?://[^"'<>\s\\]+\.(?:mp4|m3u8|webm|mkv)(?:\?[^"'<>\s\\]*)?)''',
          caseSensitive: false),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(cleaned);
      if (m != null) return absoluteUrl(embedUrl, m.group(1));
    }
  } catch (e) {
    logger.w('resolveDirectFromEmbed gagal ($embedUrl): $e');
  }
  return null;
}


/// Dilempar saat sumber meminta login / VIP / member untuk mengakses konten.
class LoginRequiredException implements Exception {
  final SourceId source;
  const LoginRequiredException(this.source);

  @override
  String toString() =>
      '${source.label} meminta login/VIP. Buka Pengaturan > Akun & Login, '
      'masuk ke ${source.label}, lalu coba lagi.';
}

/// True kalau halaman tampak seperti tembok login / VIP (bukan konten).
bool looksLikeLoginWall(dom.Document doc) {
  if (doc.querySelector('input[type="password"]') != null) return true;
  final t = (doc.body?.text ?? '').toLowerCase();
  if (t.length > 6000) return false; // halaman konten biasanya panjang
  final gate = t.contains('login') || t.contains('masuk') || t.contains('sign in');
  final tier = t.contains('vip') || t.contains('premium') || t.contains('member');
  return gate && tier;
}

/// Ambil URL gambar dari <img>, termasuk atribut lazy-load.
String? imageFromElement(dom.Element? img) {
  if (img == null) return null;
  bool ok(String? v) {
    if (v == null) return false;
    final t = v.trim();
    return t.isNotEmpty && !t.startsWith('data:') && !t.contains('placeholder');
  }

  for (final attr in const [
    'data-src', 'data-lazy-src', 'data-original', 'data-lazy', 'data-img', 'src',
  ]) {
    final v = img.attributes[attr];
    if (ok(v)) return v!.trim();
  }
  final srcset = img.attributes['data-srcset'] ?? img.attributes['srcset'];
  if (ok(srcset)) return srcset!.trim().split(',').first.trim().split(' ').first;
  return null;
}

const _kNavSegments = {
  'login', 'register', 'daftar', 'genre', 'genres', 'jadwal', 'schedule',
  'page', 'tag', 'category', 'search', 'contact', 'dmca', 'about', 'privacy',
  'faq', 'bookmark', 'history', 'user', 'vip', 'premium', 'donasi', 'donate',
  'wp-login.php', 'wp-admin', 'feed',
};
const _kDetailSegments = {'anime', 'series', 'detail', 'title', 'show', 'nonton', 'film'};

/// Parser kartu anime yang tidak bergantung pada class CSS tertentu.
///
/// Dipakai sebagai cadangan ketika selector spesifik situs tidak menemukan
/// apa pun (situs sering ganti tema). Setiap link satu-host yang punya
/// gambar dianggap kartu; link navigasi dibuang.
List<Anime> parseAnimeCardsGeneric(dom.Document doc, SourceId source, String baseUrl) {
  final host = Uri.tryParse(baseUrl)?.host ?? '';
  final found = <String, Anime>{};
  final detailLike = <String>{};

  for (final a in doc.querySelectorAll('a[href]')) {
    final href = (a.attributes['href'] ?? '').trim();
    if (href.isEmpty ||
        href.startsWith('#') ||
        href.startsWith('javascript:') ||
        href.startsWith('mailto:')) {
      continue;
    }
    final abs = absoluteUrl(baseUrl, href);
    final uri = Uri.tryParse(abs);
    if (uri == null || uri.host != host) continue;
    final segs = uri.pathSegments.where((x) => x.isNotEmpty).toList();
    if (segs.isEmpty || _kNavSegments.contains(segs.first.toLowerCase())) continue;

    var img = a.querySelector('img');
    dom.Element card = a;
    if (img == null) {
      final parent = a.parent;
      if (parent != null && parent.querySelectorAll('a[href]').length <= 2) {
        img = parent.querySelector('img');
        card = parent;
      }
    }
    final cover = imageFromElement(img);
    if (cover == null) continue;

    var title = cleanText(a.attributes['title']);
    if (title.isEmpty) title = cleanText(img?.attributes['alt']);
    if (title.isEmpty) title = cleanText(img?.attributes['title']);
    if (title.isEmpty) {
      title = cleanText(card.querySelector('h1, h2, h3, h4, .title, .tt, .ttls')?.text);
    }
    if (title.isEmpty) title = cleanText(a.text);
    if (title.length < 2) continue;

    final slug = segs.last;
    if (_kDetailSegments.contains(segs.first.toLowerCase())) detailLike.add(abs);

    final existing = found[abs];
    if (existing == null) {
      found[abs] = Anime(
        id: Anime.makeId(source, slug),
        source: source,
        title: title,
        slug: slug,
        url: abs,
        cover: absoluteUrl(baseUrl, cover),
      );
    }
  }

  // Kalau ada link bergaya /anime/<slug>, buang link lain (episode, dll).
  if (detailLike.isNotEmpty) {
    return [for (final e in found.entries) if (detailLike.contains(e.key)) e.value];
  }
  return found.values.toList();
}
