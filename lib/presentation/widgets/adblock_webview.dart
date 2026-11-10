/// WebView dengan pemblokir iklan terpasang (lihat AdblockEngine).
///
/// Dipakai untuk (1) memutar embed mirror ketika video tidak bisa di-resolve
/// langsung, dan (2) membuka halaman file-host untuk download.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/adblock/adblock_engine.dart';

typedef WebDownloadCallback = void Function(
  String url,
  String? suggestedFilename,
  String? userAgent,
);

class AdblockWebView extends StatefulWidget {
  final String url;

  /// true = navigasi top-level ke situs lain dibatalkan (untuk embed player).
  final bool lockNavigation;

  /// true = link target=_blank dibuka di WebView yang sama (untuk browser).
  final bool allowNewWindows;

  final String? referer;
  final WebDownloadCallback? onDownload;
  final ValueChanged<double>? onProgress;
  final ValueChanged<String>? onTitle;
  final ValueChanged<InAppWebViewController>? onCreated;

  const AdblockWebView({
    super.key,
    required this.url,
    this.lockNavigation = false,
    this.allowNewWindows = false,
    this.referer,
    this.onDownload,
    this.onProgress,
    this.onTitle,
    this.onCreated,
  });

  @override
  State<AdblockWebView> createState() => _AdblockWebViewState();
}

class _AdblockWebViewState extends State<AdblockWebView> {
  final AdblockEngine _engine = AdblockEngine.instance;
  InAppWebViewController? _controller;
  late final String _startHost;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startHost = Uri.tryParse(widget.url)?.host.toLowerCase() ?? '';
  }

  /// Bandingkan dua host berdasar dua label terakhir (mis. a.b.com == c.b.com).
  bool _sameSite(String a, String b) {
    String tail(String h) {
      final p = h.split('.');
      return p.length <= 2 ? h : p.sublist(p.length - 2).join('.');
    }

    return tail(a) == tail(b);
  }

  @override
  Widget build(BuildContext context) {
    final script = _engine.buildUserScript(_startHost);
    final scripts = <UserScript>[if (script != null) script];

    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(widget.url),
            headers: widget.referer != null ? {'Referer': widget.referer!} : null,
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            javaScriptCanOpenWindowsAutomatically: false,
            supportMultipleWindows: true,
            useShouldOverrideUrlLoading: true,
            // contentBlockers hanya jalan di iOS. Di Android pemblokiran request
            // (iklan video/VAST, script iklan, iframe iklan) harus lewat
            // shouldInterceptRequest.
            useShouldInterceptRequest: true,
            useOnDownloadStart: true,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
            contentBlockers: _engine.contentBlockers,
            transparentBackground: false,
          ),
          initialUserScripts: UnmodifiableListView<UserScript>(scripts),
          onWebViewCreated: (c) {
            _controller = c;
            widget.onCreated?.call(c);
          },
          shouldInterceptRequest: (controller, request) async {
            if (!_engine.enabled) return null;
            final url = request.url.toString();
            if (!url.startsWith('http')) return null;
            // Jangan blok dokumen utama situs yang sedang dibuka.
            if ((request.isForMainFrame ?? false) &&
                _sameSite(request.url.host.toLowerCase(), _startHost)) {
              return null;
            }
            if (_engine.isBlocked(url)) {
              _engine.noteBlockedQuiet();
              return WebResourceResponse(
                contentType: 'text/plain',
                contentEncoding: 'utf-8',
                statusCode: 204,
                reasonPhrase: 'No Content',
                data: Uint8List(0),
              );
            }
            return null;
          },
          shouldOverrideUrlLoading: (controller, action) async {
            final uri = action.request.url;
            if (uri == null) return NavigationActionPolicy.ALLOW;
            final u = uri.toString();

            // intent:// market:// dll. = pola redirect jahat / pembuka aplikasi lain.
            if (!u.startsWith('http://') && !u.startsWith('https://')) {
              if (_engine.enabled) _engine.noteBlocked();
              return NavigationActionPolicy.CANCEL;
            }
            if (_engine.isBlocked(u)) {
              _engine.noteBlocked();
              return NavigationActionPolicy.CANCEL;
            }
            if (widget.lockNavigation && action.isForMainFrame) {
              final host = uri.host.toLowerCase();
              if (!_sameSite(host, _startHost)) {
                if (_engine.enabled) _engine.noteBlocked();
                return NavigationActionPolicy.CANCEL;
              }
            }
            return NavigationActionPolicy.ALLOW;
          },
          onCreateWindow: (controller, action) async {
            final url = action.request.url?.toString() ?? '';
            final blocked = url.isEmpty || _engine.isBlocked(url) ||
                (_engine.enabled && _engine.blockPopups && action.hasGesture != true);
            if (blocked || !widget.allowNewWindows) {
              if (_engine.enabled) _engine.noteBlocked();
              return false;
            }
            // Buka di WebView yang sama alih-alih jendela baru.
            await controller.loadUrl(urlRequest: action.request);
            return false;
          },
          onDownloadStartRequest: (controller, req) async {
            widget.onDownload?.call(
              req.url.toString(),
              req.suggestedFilename,
              req.userAgent,
            );
          },
          onProgressChanged: (controller, progress) {
            widget.onProgress?.call(progress / 100.0);
          },
          onTitleChanged: (controller, title) {
            if (title != null) widget.onTitle?.call(title);
          },
          onLoadStart: (controller, url) {
            if (_error != null && mounted) setState(() => _error = null);
          },
          onReceivedError: (controller, request, error) {
            if ((request.isForMainFrame ?? false) && mounted) {
              setState(() => _error = error.description);
            }
          },
        ),
        if (_error != null)
          Positioned.fill(
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.white70, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'Gagal memuat halaman\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: () {
                        setState(() => _error = null);
                        _controller?.reload();
                      },
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
