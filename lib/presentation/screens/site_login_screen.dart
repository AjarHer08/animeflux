/// Login ke situs sumber lewat WebView. Setelah masuk, tekan "Simpan sesi"
/// supaya cookie dipakai scraper (Hidoristream / Otakudesu / Lendrive).
library;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/constants.dart';
import '../../core/utils/session_store.dart';
import '../widgets/glass.dart';

class SiteLoginScreen extends StatefulWidget {
  final SourceId source;
  const SiteLoginScreen({super.key, required this.source});

  @override
  State<SiteLoginScreen> createState() => _SiteLoginScreenState();
}

class _SiteLoginScreenState extends State<SiteLoginScreen> {
  double _progress = 0;

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final n = await SessionStore.instance.captureFromWebView(widget.source);
    if (!mounted) return;
    if (n == 0) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Belum ada cookie. Selesaikan login di halaman dulu.'),
      ));
      return;
    }
    messenger.showSnackBar(SnackBar(
      content: Text('Sesi ${widget.source.label} tersimpan ($n cookie).'),
    ));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassAppBar(
        title: Text('Login ${widget.source.label}'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Simpan sesi'),
            onPressed: _save,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 1) LinearProgressIndicator(value: _progress),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Masuk atau daftar seperti biasa di halaman situs, lalu tekan '
              '"Simpan sesi".',
              style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12),
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.source.baseUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
              ),
              onProgressChanged: (_, p) => setState(() => _progress = p / 100),
            ),
          ),
        ],
      ),
    );
  }
}
