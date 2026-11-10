/// Fallback fetch HTML lewat WebView headless.
///
/// Dipakai saat Dio kena proteksi Cloudflare / JS challenge (HTTP 403/503
/// atau halaman "Just a moment..."). WebView asli bisa menjalankan JavaScript
/// sehingga challenge lolos, lalu HTML hasil render diambil dari DOM.
library;

import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'logger.dart';

class WebFetcher {
  WebFetcher._();

  static bool _isChallengeTitle(String? title) {
    final t = (title ?? '').toLowerCase();
    return t.contains('just a moment') ||
        t.contains('attention required') ||
        t.contains('checking your browser') ||
        t.contains('verifying');
  }

  /// Ambil HTML final (setelah JS jalan). Melempar [TimeoutException] kalau
  /// challenge tidak selesai dalam [timeout].
  static Future<String> fetch(
    String url, {
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final completer = Completer<String>();
    Future<void> finish(InAppWebViewController c) async {
      try {
        // Tunggu challenge Cloudflare selesai (maks ~20 detik).
        for (var i = 0; i < 20; i++) {
          final title = await c.getTitle();
          if (!_isChallengeTitle(title)) break;
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        final html = await c.evaluateJavascript(
          source: 'document.documentElement.outerHTML',
        );
        if (!completer.isCompleted) {
          completer.complete('<!DOCTYPE html>${html ?? ''}');
        }
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    }

    final headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        cacheEnabled: true,
      ),
      onLoadStop: (controller, _) => finish(controller),
      onReceivedError: (controller, request, error) {
        // Error sub-resource diabaikan; hanya error main frame yang fatal.
        if (request.isForMainFrame ?? false) {
          if (!completer.isCompleted) {
            completer.completeError(Exception(error.description));
          }
        }
      },
    );

    try {
      await headless.run();
      return await completer.future.timeout(timeout);
    } finally {
      try {
        await headless.dispose();
      } catch (e) {
        logger.w('WebFetcher dispose: $e');
      }
    }
  }
}
