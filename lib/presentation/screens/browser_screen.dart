/// Browser mini dengan pemblokir iklan — untuk halaman file-host (download)
/// dan halaman episode. Download yang dipicu halaman otomatis ditangkap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/download_providers.dart';
import '../widgets/adblock_webview.dart';

class BrowserScreen extends ConsumerStatefulWidget {
  final String url;
  final String title;
  final String animeId;
  final String animeTitle;
  final String episodeTitle;
  final String? cover;

  const BrowserScreen({
    super.key,
    required this.url,
    this.title = 'Browser',
    this.animeId = 'browser',
    this.animeTitle = 'Download',
    this.episodeTitle = '',
    this.cover,
  });

  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  InAppWebViewController? _controller;
  double _progress = 0;
  String _title = '';

  Future<void> _handleDownload(String url, String? filename, String? ua) async {
    String? cookie;
    try {
      final cookies = await CookieManager.instance().getCookies(url: WebUri(url));
      cookie = cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {}
    try {
      await ref.read(downloadTasksProvider.notifier).enqueueUrl(
            animeId: widget.animeId,
            animeTitle: widget.animeTitle,
            episodeTitle: widget.episodeTitle.isEmpty ? (filename ?? 'file') : widget.episodeTitle,
            url: url,
            quality: '',
            cover: widget.cover,
            fileName: filename,
            headers: {
              if (ua != null) 'User-Agent': ua,
              if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
            },
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download dimulai — lihat di Pengaturan > Download Manager')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal download: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title.isEmpty ? widget.title : _title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
            onPressed: () => _controller?.reload(),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Buka di browser eksternal',
            onPressed: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
          ),
        ],
        bottom: _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress, minHeight: 2),
              )
            : null,
      ),
      body: AdblockWebView(
        url: widget.url,
        allowNewWindows: true,
        onCreated: (c) => _controller = c,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onTitle: (t) {
          if (mounted) setState(() => _title = t);
        },
        onDownload: _handleDownload,
      ),
    );
  }
}
