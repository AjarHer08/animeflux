/// Gambar komik dengan fallback berlapis supaya thumbnail & halaman chapter
/// tetap tampil walau CDN menolak hotlink / butuh cookie Cloudflare:
///   1) Referer sumber + cookie WebView (cf_clearance) + User-Agent WebView
///   2) hanya User-Agent (tanpa Referer / cookie)
///   3) lewat proxy gambar publik (wsrv.nl)
/// Gagal semua -> ikon rusak yang bisa diketuk untuk coba lagi.
library;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/constants.dart';
import '../../data/models/comic.dart';
import '../../data/repositories/comic_repository.dart';

/// Rapikan URL gambar: spasi, protokol relatif, dll.
String normalizeImageUrl(String raw) {
  var u = raw.trim().replaceAll('&amp;', '&');
  if (u.startsWith('//')) u = 'https:$u';
  u = u.replaceAll(' ', '%20');
  return u;
}

/// URL proxy gambar publik (dipakai sebagai cadangan terakhir).
String proxiedImageUrl(String url, {int? width}) {
  final w = width == null ? '' : '&w=$width';
  return 'https://wsrv.nl/?url=${Uri.encodeComponent(url)}$w&q=85';
}

class _Cached {
  final Map<String, String> headers;
  final DateTime at;
  _Cached(this.headers, this.at);
}

/// Header untuk memuat gambar sebuah sumber komik (termasuk cookie WebView).
class ComicImageHeaders {
  ComicImageHeaders._();

  static String? _webViewUa;
  static final Map<String, _Cached> _cache = {};

  static Map<String, String> uaOnly() => {
        'User-Agent': kDesktopUserAgents[0],
        'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      };

  static Future<Map<String, String>> build(ComicSourceId source, String url) async {
    final host = Uri.tryParse(url)?.host ?? '';
    final key = '${source.name}|$host';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at).inSeconds < 60) {
      return hit.headers;
    }
    final headers = <String, String>{
      ...comicRepository.scraperFor(source).imageHeaders,
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    };
    try {
      final byName = <String, String>{};
      final cm = CookieManager.instance();
      for (final u in <String>{url, source.baseUrl}) {
        final list = await cm.getCookies(url: WebUri(u));
        for (final c in list) {
          byName[c.name] = '${c.value}';
        }
      }
      if (byName.isNotEmpty) {
        headers['Cookie'] = byName.entries.map((e) => '${e.key}=${e.value}').join('; ');
        // cf_clearance terikat ke User-Agent WebView yang menyelesaikan challenge.
        _webViewUa ??= await InAppWebViewController.getDefaultUserAgent();
        if ((_webViewUa ?? '').isNotEmpty) headers['User-Agent'] = _webViewUa!;
      }
    } catch (_) {
      // cookie opsional
    }
    _cache[key] = _Cached(headers, DateTime.now());
    return headers;
  }

  static void clearCache() => _cache.clear();
}

class ComicNetImage extends StatefulWidget {
  final ComicSourceId source;

  /// URL jaringan (diabaikan bila [localPath] diisi).
  final String url;

  /// File lokal (chapter yang sudah diunduh).
  final String? localPath;
  final BoxFit fit;
  final double? width;

  /// Untuk thumbnail: proxy memperkecil gambar.
  final int? thumbWidth;

  /// Dipanggil sekali saat ukuran asli gambar diketahui.
  final void Function(double width, double height)? onSize;
  final Widget Function(BuildContext context)? placeholderBuilder;
  final Widget Function(BuildContext context, VoidCallback retry)? errorBuilder;

  const ComicNetImage({
    super.key,
    required this.source,
    required this.url,
    this.localPath,
    this.fit = BoxFit.cover,
    this.width,
    this.thumbWidth,
    this.onSize,
    this.placeholderBuilder,
    this.errorBuilder,
  });

  @override
  State<ComicNetImage> createState() => _ComicNetImageState();
}

class _ComicNetImageState extends State<ComicNetImage> {
  static const _lastStage = 2;
  int _stage = 0;
  bool _failed = false;
  bool _sizeReported = false;
  late Future<Map<String, String>> _headers;

  String get _url => normalizeImageUrl(widget.url);

  @override
  void initState() {
    super.initState();
    _headers = ComicImageHeaders.build(widget.source, _url);
  }

  @override
  void didUpdateWidget(covariant ComicNetImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.localPath != widget.localPath) {
      _stage = 0;
      _failed = false;
      _sizeReported = false;
      _headers = ComicImageHeaders.build(widget.source, _url);
    }
  }

  void _retry() {
    ComicImageHeaders.clearCache();
    setState(() {
      _stage = 0;
      _failed = false;
      _sizeReported = false;
      _headers = ComicImageHeaders.build(widget.source, _url);
    });
  }

  void _next(int fromStage) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Abaikan panggilan ganda untuk stage yang sama.
      if (!mounted || _stage != fromStage || _failed) return;
      setState(() {
        if (_stage < _lastStage) {
          _stage++;
        } else {
          _failed = true;
        }
      });
    });
  }

  void _listenSize(ImageProvider provider) {
    final cb = widget.onSize;
    if (cb == null || _sizeReported) return;
    _sizeReported = true;
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      stream.removeListener(listener);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) cb(w, h);
      });
    }, onError: (_, __) => stream.removeListener(listener));
    stream.addListener(listener);
  }

  Widget _placeholder(BuildContext context) {
    final b = widget.placeholderBuilder;
    if (b != null) return b(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.menu_book, size: 36, color: scheme.onSurfaceVariant),
    );
  }

  Widget _error(BuildContext context) {
    final b = widget.errorBuilder;
    if (b != null) return b(context, _retry);
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _retry,
      child: Container(
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.broken_image, size: 36, color: scheme.onSurfaceVariant),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.localPath;
    if (local != null) {
      final provider = FileImage(File(local));
      _listenSize(provider);
      return Image(
        image: provider,
        fit: widget.fit,
        width: widget.width,
        errorBuilder: (c, _, __) => _error(c),
      );
    }
    if (_failed) return _error(context);

    return FutureBuilder<Map<String, String>>(
      future: _headers,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return _placeholder(context);
        final String url;
        final Map<String, String> headers;
        if (_stage == 0) {
          url = _url;
          headers = snap.data ?? ComicImageHeaders.uaOnly();
        } else if (_stage == 1) {
          url = _url;
          headers = ComicImageHeaders.uaOnly();
        } else {
          url = proxiedImageUrl(_url, width: widget.thumbWidth);
          headers = const {};
        }
        final stageNow = _stage;
        return CachedNetworkImage(
          key: ValueKey('$url|$stageNow'),
          imageUrl: url,
          httpHeaders: headers,
          imageBuilder: (context, provider) {
            _listenSize(provider);
            return Image(image: provider, fit: widget.fit, width: widget.width);
          },
          placeholder: (c, _) => _placeholder(c),
          errorWidget: (c, _, __) {
            _next(stageNow);
            return _placeholder(c);
          },
        );
      },
    );
  }
}
