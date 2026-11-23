/// Resolusi link download agar file diunduh di dalam aplikasi, bukan dibuka
/// di browser.
library;

import 'package:dio/dio.dart';

import '../../core/utils/html_utils.dart';
import '../../core/utils/http_client.dart';
import '../../core/utils/logger.dart';
import '../scrapers/scraper_utils.dart';

class ResolvedDownload {
  /// URL file yang siap diunduh download manager.
  final String url;
  final String? fileName;
  final String? referer;

  const ResolvedDownload(this.url, {this.fileName, this.referer});
}

/// Coba ubah link download (link langsung, shortlink, atau halaman file-host)
/// menjadi URL file yang bisa diunduh di dalam aplikasi.
///
/// Return `null` kalau link hanya halaman perantara (iklan/safelink) yang
/// tidak bisa diurai tanpa membuka halaman itu.
Future<ResolvedDownload?> resolveInAppDownload(
  String url, {
  String? referer,
}) async {
  if (url.isEmpty) return null;
  try {
    if (isDirectMediaUrl(url)) {
      return ResolvedDownload(url, fileName: _fileName(url), referer: referer);
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();

    // Pixeldrain: /u/<id> atau /l/<id> -> endpoint file langsung.
    if (host.contains('pixeldrain.com')) {
      final m = RegExp(r'/(?:u|l)/([A-Za-z0-9_-]+)').firstMatch(uri.path);
      if (m != null) {
        return ResolvedDownload(
          'https://pixeldrain.com/api/file/${m.group(1)}?download',
          fileName: _fileName(uri.path),
          referer: referer,
        );
      }
    }

    // Google Drive: /file/d/<id>/view -> unduh langsung.
    if (host.contains('drive.google.com') || host == 'docs.google.com') {
      final m = RegExp(r'/d/([A-Za-z0-9_-]{10,})').firstMatch(uri.path) ??
          RegExp(r'[?&]id=([A-Za-z0-9_-]{10,})').firstMatch(uri.query);
      if (m != null) {
        return ResolvedDownload(
          'https://drive.google.com/uc?export=download&id=${m.group(1)}',
          referer: referer,
        );
      }
    }

    // Mediafire: tombol Download di halaman file menuju URL file langsung.
    if (host.contains('mediafire.com')) {
      final html = await _fetch(url, referer: referer);
      if (html != null) {
        final doc = parseHtml(html);
        final button = doc.querySelector(
          '#downloadButton, a.input.popsok, a[aria-label="Download file"]',
        );
        final href = button?.attributes['href'];
        if (href != null && href.startsWith('http')) {
          return ResolvedDownload(href, fileName: _fileName(href), referer: referer);
        }
        final m = RegExp(r'''(https?://download[^\s"'<>]+\.mediafire\.com/[^\s"'<>]+)''')
            .firstMatch(html);
        if (m != null) {
          return ResolvedDownload(m.group(1)!, referer: referer);
        }
      }
    }

    // Halaman lain: cari tautan file langsung di dalam HTML-nya.
    final html = await _fetch(url, referer: referer);
    if (html == null) return null;
    final direct = _mediaLinkInHtml(html, base: url);
    if (direct != null) {
      return ResolvedDownload(direct, fileName: _fileName(direct), referer: referer);
    }

    // Halaman perantara iklan/safelink: biarkan dibuka di WebView dalam
    // aplikasi (bukan browser eksternal).
    return null;
  } catch (e) {
    logger.w('resolveInAppDownload gagal ($url): $e');
    return null;
  }
}

Future<String?> _fetch(String url, {String? referer}) async {
  try {
    final res = await HttpClient.instance.raw.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        maxRedirects: 8,
        validateStatus: (s) => s != null && s < 400,
        headers: {if (referer != null) 'Referer': referer},
      ),
    );
    if ((res.statusCode ?? 0) >= 400) return null;
    return res.data ?? '';
  } catch (_) {
    return null;
  }
}

String? _mediaLinkInHtml(String html, {required String base}) {
  final cleaned = html.replaceAll(r'\/', '/').replaceAll('&amp;', '&');
  final doc = parseHtml(cleaned);
  for (final a in doc.querySelectorAll('a[href]')) {
    final href = absoluteUrl(base, a.attributes['href']);
    if (href.isEmpty) continue;
    if (isDirectMediaUrl(href)) return href;
    if (a.attributes.containsKey('download') &&
        (href.startsWith('http://') || href.startsWith('https://'))) {
      return href;
    }
  }
  return null;
}

String? _fileName(String url) {
  final name = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
  if (name == null || name.isEmpty || !name.contains('.')) return null;
  return name;
}
