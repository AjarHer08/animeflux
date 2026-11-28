/// HTTP client wrapper dengan User-Agent rotation + retry + fallback WebView.
library;

import 'package:dio/dio.dart';

import '../../core/constants.dart';
import 'logger.dart';
import 'web_fetcher.dart';

class HttpClient {
  HttpClient._() : _dio = _buildDio();

  static final HttpClient instance = HttpClient._();

  final Dio _dio;

  /// Host yang terbukti butuh WebView (Cloudflare challenge) — langsung
  /// lewat WebView untuk request berikutnya supaya tidak gagal berulang.
  static final Set<String> _webViewHosts = <String>{};

  static Dio _buildDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      maxRedirects: 5,
      // Semua status ditangani manual di getHtml (403/503 -> fallback WebView).
      validateStatus: (s) => s != null,
      responseType: ResponseType.plain,
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // UA TETAP: rotasi UA tiap request membuat Cloudflare/WAF kadang menolak
        // (penyebab hasil pencarian "kadang ada kadang tidak").
        options.headers['User-Agent'] = kDesktopUserAgents[0];
        // Jangan timpa header yang sudah diisi pemanggil (mis. Referer/Accept).
        kDefaultHeaders.forEach((k, v) => options.headers.putIfAbsent(k, () => v));
        if (options.headers['Referer'] == null) {
          options.headers['Referer'] = '${options.uri.origin}/';
        }
        return handler.next(options);
      },
      onError: (e, handler) async {
        // Retry sekali untuk error koneksi.
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError) {
          try {
            final retry = await _buildDio().fetch(e.requestOptions);
            return handler.resolve(retry);
          } catch (_) {}
        }
        return handler.next(e);
      },
    ));

    return dio;
  }

  static bool _looksLikeChallenge(String body) {
    if (body.length > 60000) return false; // halaman asli biasanya besar
    final b = body.toLowerCase();
    return b.contains('just a moment...') ||
        b.contains('cf-browser-verification') ||
        b.contains('challenge-platform') ||
        b.contains('attention required! | cloudflare');
  }

  Future<String> getHtml(String url, {Map<String, String>? extraHeaders}) async {
    final host = Uri.tryParse(url)?.host ?? '';
    if (_webViewHosts.contains(host)) {
      return WebFetcher.fetch(url);
    }

    Response<String>? res;
    Object? netError;
    // Maks 3 percobaan untuk gangguan sesaat: error jaringan, 5xx/429, atau
    // body kosong. Jeda singkat bertambah tiap percobaan.
    for (var attempt = 0; attempt < 3; attempt++) {
      res = null;
      netError = null;
      try {
        res = await _dio.get<String>(
          url,
          options: Options(headers: extraHeaders, responseType: ResponseType.plain),
        );
      } catch (e) {
        netError = e;
      }
      final c = res?.statusCode ?? 0;
      final b = res?.data ?? '';
      final transient = netError != null ||
          c == 429 ||
          c >= 500 && c != 503 ||
          ((c == 200 || c == 201) && b.trim().length < 200);
      if (!transient) break;
      await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
    }

    final code = res?.statusCode ?? 0;
    final body = res?.data ?? '';

    if (res != null &&
        (code == 200 || code == 201) &&
        body.trim().length >= 200 &&
        !_looksLikeChallenge(body)) {
      return body;
    }

    // Diblokir / challenge -> coba WebView headless.
    final blocked = code == 403 || code == 429 || code == 503 ||
        (res != null && code == 200 && _looksLikeChallenge(body)) ||
        (res != null && code == 200 && body.trim().length < 200);
    if (blocked) {
      try {
        final html = await WebFetcher.fetch(url);
        _webViewHosts.add(host);
        return html;
      } catch (e) {
        logger.w('WebFetcher gagal untuk $url: $e');
      }
    }

    if (res != null) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        message: 'HTTP $code untuk $url',
      );
    }
    throw netError ?? Exception('Gagal memuat $url');
  }

  /// Ambil HTML hasil render WebView (JS jalan) — untuk halaman yang daftarnya
  /// dimuat lewat JavaScript.
  Future<String> getHtmlRendered(String url) =>
      WebFetcher.fetch(url, settle: const Duration(seconds: 3));

  /// POST form (dipakai AJAX admin-ajax.php WordPress).
  Future<String> postForm(
    String url,
    Map<String, dynamic> data, {
    Map<String, String>? headers,
  }) async {
    final res = await _dio.post<String>(
      url,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Origin': Uri.parse(url).origin,
          ...?headers,
        },
        responseType: ResponseType.plain,
      ),
    );
    final code = res.statusCode ?? 0;
    if (code >= 200 && code < 300) return res.data ?? '';
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      message: 'HTTP $code untuk POST $url',
    );
  }

  Dio get raw => _dio;
}
