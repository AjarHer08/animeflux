/// Penyimpan sesi login situs sumber (cookie per host).
///
/// Login dilakukan lewat WebView (lihat SiteLoginScreen). Cookie hasilnya
/// disimpan di sini lalu otomatis ditempel ke request Dio oleh [HttpClient].
/// WebFetcher memakai cookie jar WebView yang sama, jadi sudah ikut login.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../constants.dart';
import '../theme/app_theme.dart' show sharedPreferencesInstance;

class SessionStore extends ChangeNotifier {
  SessionStore._();
  static final SessionStore instance = SessionStore._();

  static String _key(String host) => 'session_cookie::$host';

  String? cookieFor(String host) {
    try {
      final v = sharedPreferencesInstance.getString(_key(host));
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  bool isLoggedIn(SourceId source) =>
      cookieFor(Uri.parse(source.baseUrl).host) != null;

  /// Baca cookie dari WebView untuk [source] lalu simpan. Return jumlah cookie.
  Future<int> captureFromWebView(SourceId source) async {
    final url = WebUri(source.baseUrl);
    final cookies = await CookieManager.instance().getCookies(url: url);
    if (cookies.isEmpty) return 0;
    final header = cookies.map((c) => '${c.name}=${c.value}').join('; ');
    await sharedPreferencesInstance.setString(
      _key(Uri.parse(source.baseUrl).host),
      header,
    );
    notifyListeners();
    return cookies.length;
  }

  Future<void> logout(SourceId source) async {
    final host = Uri.parse(source.baseUrl).host;
    await sharedPreferencesInstance.remove(_key(host));
    try {
      await CookieManager.instance().deleteCookies(url: WebUri(source.baseUrl));
    } catch (_) {}
    notifyListeners();
  }
}
