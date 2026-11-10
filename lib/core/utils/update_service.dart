/// Cek pembaruan lewat GitHub Releases (AjarHer08/animeflux).
library;

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../constants.dart';
import '../theme/app_theme.dart' show sharedPreferencesInstance;
import 'logger.dart';

const kGithubRepo = 'AjarHer08/animeflux';

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String notes;
  final String releaseUrl;
  final Map<String, String> assets; // nama file -> url unduh
  final bool hasUpdate;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.notes,
    required this.releaseUrl,
    required this.assets,
    required this.hasUpdate,
  });

  /// URL unduhan terbaik: universal APK kalau ada, selain itu halaman rilis.
  String get downloadUrl {
    for (final e in assets.entries) {
      if (e.key.toLowerCase().contains('universal')) return e.value;
    }
    return releaseUrl;
  }
}

class UpdateService {
  UpdateService._();

  static const _lastCheckKey = 'update_last_check_v1';

  /// Bandingkan versi "1.0.1" / "v1.0.1+2". Return >0 kalau [a] lebih baru.
  static int compareVersions(String a, String b) {
    List<int> parse(String v) {
      final core = v.trim().replaceFirst(RegExp(r'^[vV]'), '').split(RegExp(r'[+\-]')).first;
      return core.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    }

    final pa = parse(a), pb = parse(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }

  /// Lempar exception kalau gagal (jaringan / belum ada rilis).
  static Future<UpdateInfo> check() async {
    String current = kAppVersion;
    try {
      current = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/vnd.github+json'},
    ));
    final res = await dio.get<Map<String, dynamic>>(
      'https://api.github.com/repos/$kGithubRepo/releases/latest',
    );
    final data = res.data ?? const {};
    final tag = (data['tag_name'] ?? '').toString();
    if (tag.isEmpty) throw Exception('Belum ada rilis di GitHub.');

    final assets = <String, String>{};
    for (final a in (data['assets'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(a as Map);
      final name = (m['name'] ?? '').toString();
      final url = (m['browser_download_url'] ?? '').toString();
      if (name.endsWith('.apk') && url.isNotEmpty) assets[name] = url;
    }

    try {
      await sharedPreferencesInstance.setInt(
          _lastCheckKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}

    return UpdateInfo(
      currentVersion: current,
      latestVersion: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      notes: (data['body'] ?? '').toString().trim(),
      releaseUrl: (data['html_url'] ?? 'https://github.com/$kGithubRepo/releases').toString(),
      assets: assets,
      hasUpdate: compareVersions(tag, current) > 0,
    );
  }

  /// Cek otomatis saat start: maksimal 1x per 12 jam, gagal = diam.
  static Future<UpdateInfo?> checkIfDue() async {
    try {
      final last = sharedPreferencesInstance.getInt(_lastCheckKey) ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - last;
      if (age < const Duration(hours: 12).inMilliseconds) return null;
      final info = await check();
      return info.hasUpdate ? info : null;
    } catch (e) {
      logger.w('Cek update otomatis gagal: $e');
      return null;
    }
  }
}
