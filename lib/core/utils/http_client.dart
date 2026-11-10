/// HTTP client wrapper dengan User-Agent rotation + retry + fallback WebView.
library;

import 'package:dio/dio.dart';

import '../../core/constants.dart';
import 'logger.dart';
import 'session_store.dart';
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
        options.headers['User-Agent'] =
            kDesktopUserAgents[DateTime.now().microsecond % kDesktopUserAgents.length];
        // Jangan timpa header yang sudah diisi pemanggil (mis. Referer/Accept).
        kDefaultHeaders.forEach((k, v) => options.headers.putIfAbsent(k, () => v));
        // Sesi login situs (kalau user sudah masuk lewat WebView).
        if (options.headers['Cookie'] == null) {
          final cookie = SessionStore.instance.cookieFor(options.uri.host);
          if (cookie != null) options.headers['Cookie'] = cookie;
        }
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
    try {
      res = await _dio.get<String>(
        url,
        options: Options(headers: extraHeaders, responseType: ResponseType.plain),
      );
    } catch (e) {
      netError = e;
    }

    final code = res?.statusCode ?? 0;
    final body = res?.data ?? '';

    if (res != null && (code == 200 || code == 201) && !_looksLikeChallenge(body)) {
      return body;
    }

    // Diblokir / challenge -> coba WebView headless.
    final blocked = code == 403 || code == 429 || code == 503 ||
        (res != null && code == 200 && _looksLikeChallenge(body));
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
