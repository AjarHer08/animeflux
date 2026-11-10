/// Scraper untuk Lendrive (lendrive.web.id)
/// Lendrive fokus ke download MKV/MP4 720p/1080p HEVC.
library;

import '../../core/constants.dart';
import '../../core/utils/html_utils.dart';
import '../../core/utils/http_client.dart';
import '../models/anime.dart';
import '../models/episode.dart';
import '../models/genre.dart';
import '../models/schedule.dart';
import 'base_scraper.dart';
import 'scraper_utils.dart';

class LendriveScraper implements BaseScraper {
  @override
  SourceId get source => SourceId.lendrive;

  @override
  String get baseUrl => source.baseUrl;

  final _http = HttpClient.instance;

  @override
  Future<List<Anime>> getLatest({int page = 1}) async {
    final url = page <= 1 ? '$baseUrl/' : '$baseUrl/home?page=$page';
    return _parseHomeGrid(url);
  }

  @override
  Future<List<Anime>> getOngoing({int page = 1}) async {
    final url = '$baseUrl/ongoing';
    return _parseAnimeList(url);
  }

  @override
  Future<List<Anime>> getCompleted({int page = 1}) async {
    final url = '$baseUrl/completed';
    return _parseAnimeList(url);
  }

  @override
  Future<Anime> getDetail(Anime anime) async {
    final html = await _http.getHtml(anime.url);
    final doc = parseHtml(html);

    // Lendrive pakai format berbeda: biasanya content text-based dengan link
    final infoSection = doc.querySelector('.anime-info, .infox, .anime-detail, .detail-info, .entry-content');
    final genres = <Genre>[];
    String? status, type, totalEps, score, studio, release, season;
    if (infoSection != null) {
      // Pattern: "Status: Ongoing"
      final stMatch = RegExp(r'status\s*:?\s*(\w+)', caseSensitive: false).firstMatch(infoSection.text);
      if (stMatch != null) status = cleanText(stMatch.group(1));
      final tyMatch = RegExp(r'type\s*:?\s*(\w+)', caseSensitive: false).firstMatch(infoSection.text);
      if (tyMatch != null) type = cleanText(tyMatch.group(1));
      final epMatch = RegExp(r'(?:total\s*eps(?:ode)?|eps(?:ode)?)\s*:?\s*(\d+)', caseSensitive: false).firstMatch(infoSection.text);
      if (epMatch != null) totalEps = epMatch.group(1);
      // Genres dari link
      infoSection.querySelectorAll('a').forEach((a) {
        final href = a.attributes['href'] ?? '';
        if (href.contains('/genres/') || href.contains('/genre/')) {
          final name = cleanText(a.text);
          if (name.isNotEmpty && !genres.any((g) => g.name == name)) {
            genres.add(Genre(name: name, url: href));
          }
        }
      });
    }

    final synopsis = cleanText(
      doc.querySelector('.sinopsis, .desc, .sinopc, .entry-content p')?.text,
    );

    // Episode list — Lendrive biasanya per episode link atau batch per season
    final episodes = <Episode>[];
    doc.querySelectorAll('.eplister a, .episode-list a, .episodelist a, .entry-content a, table a, ul li a')
        .forEach((a) {
      final href = a.attributes['href'] ?? '';
      final title = cleanText(a.text);
      // Filter: hanya link yang mengandung "episode" atau "batch"
      if (href.contains(baseUrl) &&
          (title.toLowerCase().contains('episode') ||
              title.toLowerCase().contains('eps') ||
              title.toLowerCase().contains('batch'))) {
        final numberMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(title);
        episodes.add(Episode(
          id: '${anime.id}::${href.hashCode}',
          animeId: anime.id,
          source: source,
          title: title,
          slug: href.split('/').where((s) => s.isNotEmpty).lastOrNull,
          url: href,
          number: numberMatch?.group(1),
        ));
      }
    });

    return anime.copyWith(
      status: status ?? anime.status,
      type: type ?? anime.type,
      totalEpisodes: totalEps != null ? int.tryParse(totalEps) : anime.totalEpisodes,
      genres: genres.isNotEmpty ? genres : anime.genres,
      synopsis: synopsis.isNotEmpty ? synopsis : anime.synopsis,
      episodes: episodes,
    );
  }

  @override
  Future<Episode> getEpisodeDetail(Episode episode) async {
    final html = await _http.getHtml(episode.url);
    final doc = parseHtml(html);

    final mirrors = <StreamMirror>[];
    final downloads = <DownloadOption>[];
    final seenDl = <String>{};

    void addDownload(String? href, String resLabel, String text) {
      if (href == null || href.isEmpty || href == '#' || href.startsWith('javascript:')) return;
      final url = absoluteUrl(baseUrl, href);
      if (url.isEmpty || !seenDl.add(url)) return;
      final label = text.isEmpty ? resLabel : (resLabel.isEmpty ? text : '$resLabel $text');
      downloads.add(DownloadOption(
        label: label,
        quality: VideoQuality.fromLabel(resLabel) ?? VideoQuality.fromLabel(label),
        url: url,
        host: detectServer(url),
      ));
    }

    // Tabel download: kolom pertama = resolusi, kolom lain = link per host.
    for (final table in doc.querySelectorAll('table.download-table, .dl-table, table')) {
      for (final row in table.querySelectorAll('tr')) {
        final cells = row.querySelectorAll('td, th');
        if (cells.length < 2) continue;
        final resLabel = cleanText(cells.first.text);
        for (var i = 1; i < cells.length; i++) {
          for (final a in cells[i].querySelectorAll('a[href]')) {
            addDownload(a.attributes['href'], resLabel, cleanText(a.text));
          }
        }
      }
    }

    // Parser generik (container .download, li/strong, dst.) sebagai pelengkap.
    for (final d in parseDownloadLinks(doc, baseUrl)) {
      if (seenDl.add(d.url)) downloads.add(d);
    }

    // Streaming: iframe default + link stream.
    final defaultEmbed = firstIframeSrc(doc, baseUrl);
    if (defaultEmbed != null) {
      mirrors.add(StreamMirror(
        id: '${episode.id}::${defaultEmbed.hashCode}',
        label: 'Default',
        server: detectServer(defaultEmbed),
        embedUrl: defaultEmbed,
        downloads: downloads,
      ));
    }
    for (final a in doc.querySelectorAll('.responsive-stream a, .stream-link, .mblink, .watch-online a')) {
      final href = a.attributes['href'];
      if (href == null || href.isEmpty || href == '#') continue;
      final embed = absoluteUrl(baseUrl, href);
      mirrors.add(StreamMirror(
        id: '${episode.id}::${embed.hashCode}',
        label: cleanText(a.text).isEmpty ? 'Mirror ${mirrors.length + 1}' : cleanText(a.text),
        server: detectServer(embed),
        embedUrl: embed,
        downloads: downloads,
      ));
    }

    // Tidak ada mirror khusus stream -> pakai link download sebagai mirror
    // (player akan resolve / fallback ke WebView).
    if (mirrors.isEmpty) {
      for (final dl in downloads) {
        mirrors.add(StreamMirror(
          id: '${episode.id}::${dl.url.hashCode}',
          label: dl.label,
          server: dl.host ?? 'other',
          embedUrl: dl.url,
          downloads: downloads,
        ));
      }
    }

    return episode.copyWith(mirrors: mirrors, downloads: downloads);
  }

  @override
  Future<String?> resolveMirrorEmbed(StreamMirror mirror) async =>
      mirror.embedUrl.isEmpty ? null : mirror.embedUrl;

  @override
  Future<List<Anime>> search(String query) async {
    final url = '$baseUrl/?s=${Uri.encodeQueryComponent(query)}';
    return _parseHomeGrid(url);
  }

  @override
  Future<List<Genre>> getGenres() async {
    final html = await _http.getHtml('$baseUrl/genres');
    final doc = parseHtml(html);
    final genres = <Genre>[];
    doc.querySelectorAll('.genre-list a, .genres a, ul a[href*="/genre"]').forEach((a) {
      final name = cleanText(a.text);
      final href = a.attributes['href'];
      if (name.isNotEmpty && href != null) {
        genres.add(Genre(name: name, url: href));
      }
    });
    return genres;
  }

  @override
  Future<List<Anime>> getByGenre(Genre genre, {int page = 1}) async {
    if (genre.url == null) return [];
    return _parseHomeGrid(genre.url!);
  }

  @override
  Future<List<DaySchedule>> getSchedule() async {
    final html = await _http.getHtml(baseUrl);
    final doc = parseHtml(html);
    final days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    final result = <DaySchedule>[];
    for (final day in days) {
      final entries = <ScheduleEntry>[];
      // Lendrive punya section schedule per hari
      final daySection = doc.querySelector('#$day, .day-$day, [data-day="$day"]');
      if (daySection == null) continue;
      daySection.querySelectorAll('a').forEach((a) {
        final href = a.attributes['href'];
        final title = cleanText(a.text);
        if (title.isNotEmpty) {
          entries.add(ScheduleEntry(
            source: source,
            day: day,
            animeTitle: title,
            animeUrl: href,
          ));
        }
      });
      result.add(DaySchedule(day: day, entries: entries));
    }
    return result;
  }

  @override
  Future<String?> resolveDirectUrl(String embedUrl) => resolveDirectFromEmbed(embedUrl);

  Future<List<Anime>> _parseHomeGrid(String url) async {
    final html = await _http.getHtml(url);
    final doc = parseHtml(html);
    final list = <Anime>[];
    doc.querySelectorAll('.rel, .rel1, .col, .col-md-4, .card, article, .item').forEach((card) {
      final a = card.querySelector('a[href*="anime"], a[href*="/anime"], h2 a, h3 a, .tt a');
      if (a == null) return;
      final href = a.attributes['href'];
      if (href == null || !href.contains(baseUrl)) return;
      final title = cleanText(card.querySelector('h2, h3, .title, .tt, .ttls')?.text ?? a.text);
      final cover = card.querySelector('img')?.attributes['src'] ??
          card.querySelector('img')?.attributes['data-src'];
      final slug = href.split('/').where((s) => s.isNotEmpty).lastOrNull;
      list.add(Anime(
        id: Anime.makeId(source, slug ?? href),
        source: source,
        title: title,
        slug: slug ?? '',
        url: href,
        cover: cover,
      ));
    });
    return list;
  }

  Future<List<Anime>> _parseAnimeList(String url) async {
    return _parseHomeGrid(url);
  }
}
