/// Fallback fetch HTML lewat WebView headless.
///
/// Dipakai saat Dio kena proteksi Cloudflare / JS challenge (HTTP 403/503
/// atau halaman "Just a moment..."). WebView asli bisa menjalankan JavaScript
/// sehingga challenge lolos, lalu HTML hasil render diambil dari DOM.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

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
    Duration settle = Duration.zero,
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
        // Beri waktu skrip situs memasang gambar/daftar (halaman yang dimuat JS).
        if (settle > Duration.zero) await Future<void>.delayed(settle);
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

  /// Ambil URL gambar halaman chapter langsung dari DOM hidup: buka halaman di
  /// WebView tersembunyi, gulir sampai bawah (memicu lazy-load), lalu pilih
  /// kelompok gambar besar terbanyak dalam satu kontainer (di luar
  /// sidebar/header/footer/rekomendasi). Tidak bergantung pada nama class situs.
  static Future<List<String>> fetchImages(
    String url, {
    Duration timeout = const Duration(seconds: 70),
  }) async {
    final completer = Completer<List<String>>();

    Future<void> finish(InAppWebViewController c) async {
      try {
        for (var i = 0; i < 20; i++) {
          if (!_isChallengeTitle(await c.getTitle())) break;
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        final res = await c.callAsyncJavaScript(functionBody: _collectImagesJs);
        final raw = res?.value;
        final out = <String>[];
        if (raw is String && raw.isNotEmpty) {
          final j = jsonDecode(raw);
          if (j is List) {
            for (final e in j) {
              if (e is String && e.isNotEmpty) out.add(e);
            }
          }
        }
        if (!completer.isCompleted) completer.complete(out);
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    }

    final headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSize: const Size(540, 960),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        cacheEnabled: true,
      ),
      onLoadStop: (controller, _) => finish(controller),
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? false) {
          if (!completer.isCompleted) completer.completeError(Exception(error.description));
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

  static const String _collectImagesJs = r"""
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// 1) Gulir bertahap agar gambar lazy-load terpasang.
let stable = 0, lastH = 0;
for (let i = 0; i < 80; i++) {
  window.scrollBy(0, Math.max(400, window.innerHeight * 0.8));
  await sleep(300);
  const h = document.documentElement.scrollHeight;
  const atEnd = window.scrollY + window.innerHeight >= h - 5;
  if (atEnd && h === lastH) { stable++; } else { stable = 0; }
  lastH = h;
  if (stable >= 3) break;
}
window.scrollTo(0, 0);
await sleep(800);

const noise = 'aside, nav, header, footer, .widget, [class*="sidebar"], [class*="related"], ' +
  '[class*="popular"], [class*="recommend"], [class*="rekomendasi"], [id*="sidebar"], [class*="comment"]';
const srcOf = (i) => {
  const s = i.currentSrc || i.getAttribute('data-src') || i.getAttribute('data-lazy-src') ||
            i.getAttribute('data-original') || i.getAttribute('data-cfsrc') || i.src || '';
  if (!s || s.startsWith('data:')) return '';
  try { return new URL(s, location.href).href; } catch (e) { return ''; }
};
const cand = [...document.images].filter((i) => {
  const w = i.naturalWidth || i.width, h = i.naturalHeight || i.height;
  if (w < 300 || h < 250) return false;
  if (i.closest(noise)) return false;
  return srcOf(i) !== '';
});
if (cand.length === 0) return '[]';

// 2) Pilih kontainer leluhur yang memuat gambar besar terbanyak (seri < 6 tingkat).
const counts = new Map();
for (const i of cand) {
  let p = i.parentElement;
  for (let d = 0; d < 6 && p && p !== document.body; d++, p = p.parentElement) {
    counts.set(p, (counts.get(p) || 0) + 1);
  }
}
let best = null, bestN = 0;
for (const [el, n] of counts) {
  if (n > bestN || (n === bestN && best && best.contains(el))) { best = el; bestN = n; }
}
const inBest = best ? cand.filter((i) => best.contains(i)) : cand;
const seen = new Set(), out = [];
for (const i of inBest) { const s = srcOf(i); if (!seen.has(s)) { seen.add(s); out.push(s); } }
return JSON.stringify(out);
""";
}
