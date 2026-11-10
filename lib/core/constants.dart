/// Konstanta global aplikasi AnimeFlux
library;

/// Versi aplikasi
const String kAppVersion = '1.1.1';
const String kAppName = 'AnimeFlux';

/// Daftar sumber anime yang didukung.
/// User bisa memilih sumber per anime di detail page (parallel mode).
enum SourceId { otakudesu, hidoristream, lendrive }

extension SourceIdX on SourceId {
  String get label {
    switch (this) {
      case SourceId.otakudesu:
        return 'Otakudesu';
      case SourceId.hidoristream:
        return 'Hidoristream';
      case SourceId.lendrive:
        return 'Lendrive';
    }
  }

  String get baseUrl {
    switch (this) {
      case SourceId.otakudesu:
        return 'https://otakudesu.blog';
      case SourceId.hidoristream:
        return 'https://v10.hidoristream.online';
      case SourceId.lendrive:
        return 'https://lendrive.web.id';
    }
  }

  String get id => name;
}

/// Resolusi video yang didukung player.
enum VideoQuality {
  q360('360p', 360),
  q480('480p', 480),
  q720('720p', 720),
  q1080('1080p', 1080),
  q1080hevc('1080p HEVC', 1080);

  final String label;
  final int height;
  const VideoQuality(this.label, this.height);

  static VideoQuality? fromLabel(String label) {
    for (final q in values) {
      if (label.toLowerCase().contains(q.label.toLowerCase()) ||
          label.contains('${q.height}')) {
        return q;
      }
    }
    return null;
  }
}

/// Storage keys
class StorageKeys {
  static const favorites = 'favorites_v1';
  static const history = 'history_v1';
  static const settings = 'settings_v1';
  static const resumePositions = 'resume_v1';
}

/// User-Agent spoofing agar tidak di-block Cloudflare / WAF.
/// Pakai UA Chrome desktop modern — server biasanya whitelist browser populer.
const List<String> kDesktopUserAgents = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
];

/// Headers umum untuk request HTTP ke sumber scraping.
const Map<String, String> kDefaultHeaders = {
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
  'Accept-Language': 'id,en-US;q=0.9,en;q=0.8',
  'Upgrade-Insecure-Requests': '1',
  'Sec-Fetch-Dest': 'document',
  'Sec-Fetch-Mode': 'navigate',
  'Sec-Fetch-Site': 'none',
  'Sec-Fetch-User': '?1',
};
