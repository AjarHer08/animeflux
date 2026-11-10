/// Scraper untuk Hidoristream (v10.hidoristream.online)
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

class HidoristreamScraper implements BaseScraper {
  @override
  SourceId get source => SourceId.hidoristream;

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
    final url = '$baseUrl/daftar-ongoing';
    return _parseAnimeList(url);
  }

  @override
  Future<List<Anime>> getCompleted({int page = 1}) async {
    final url = '$baseUrl/completed-anime';
    return _parseAnimeList(url);
  }

  @override
  Future<Anime> getDetail(Anime anime) async {
    final html = await _http.getHtml(anime.url);
    final doc = parseHtml(html);

    // Info block
    final infoBlock = doc.querySelector('.anime-info, .infox, .info-palet, .detail-info');
    final infoRows = infoBlock?.querySelectorAll('li, p, .infolist li');
    String? status, type, totalEps, score, studio, release, season;
    final genres = <Genre>[];
    if (infoRows != null) {
      for (final row in infoRows) {
        final text = cleanText(row.text).toLowerCase();
        final value = cleanText(row.text.split(':').skip(1).join(':'));
        if (text.contains('genre')) {
          row.querySelectorAll('a').forEach((a) {
            final name = cleanText(a.text);
            if (name.isNotEmpty) {
              genres.add(Genre(
                name: name,
                url: a.attributes['href'],
              ));
            }
          });
        } else if (text.contains('status')) {
          status = value;
        } else if (text.contains('type')) {
          type = value;
        } else if (text.contains('total') && text.contains('eps')) {
          totalEps = RegExp(r'(\d+)').firstMatch(value)?.group(1);
        } else if (text.contains('score')) {
          score = RegExp(r'(\d+\.?\d*)').firstMatch(value)?.group(1);
        } else if (text.contains('studio')) {
          studio = value;
        } else if (text.contains('release') || text.contains('rilis')) {
          release = value;
        } else if (text.contains('season')) {
          season = value;
        }
      }
    }

    // Sinopsis
    final synopsis = cleanText(
      doc.querySelector('.sinopsis, .desc, .sinopc, [class*="sinop"]')?.text,
    );

    // Episode list — Hidoristream pakai list di bagian "Episode List"
    final episodes = <Episode>[];
    doc.querySelectorAll('.eplister a, .episode-list a, .episodelist a, ul#episodes li a').forEach((a) {
      final href = a.attributes['href'];
      final title = cleanText(a.text);
      if (href == null || title.isEmpty) return;
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
    });

    return anime.copyWith(
      status: status ?? anime.status,
      type: type ?? anime.type,
      totalEpisodes: totalEps != null ? int.tryParse(totalEps) : anime.totalEpisodes,
      score: score != null ? double.tryParse(score) : anime.score,
      studio: studio ?? anime.studio,
      releaseDate: release ?? anime.releaseDate,
      season: season ?? anime.season,
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
    final seen = <String>{};

    void addMirror(String label, String embed) {
      if (embed.isEmpty || !seen.add(embed)) return;
      mirrors.add(StreamMirror(
        id: '${episode.id}::${embed.hashCode}',
        label: label.isEmpty ? 'Mirror ${mirrors.length + 1}' : label,
        server: detectServer(embed),
        embedUrl: embed,
      ));
    }

    // Player default (iframe di HTML).
    final defaultEmbed = firstIframeSrc(doc, baseUrl);
    if (defaultEmbed != null) addMirror('Default', defaultEmbed);

    // <select> server: value bisa URL, URL relatif, atau base64 (URL / iframe).
    for (final opt in doc.querySelectorAll(
        'select.change-server option, select.mirrorstream option, #server option, select.mirror option')) {
      final value = (opt.attributes['value'] ?? '').trim();
      if (value.isEmpty) continue;
      final label = cleanText(opt.text);
      String? embed;
      if (value.startsWith('http') || value.startsWith('//') || value.startsWith('/')) {
        embed = absoluteUrl(baseUrl, value);
      } else {
        final decoded = tryBase64Decode(value);
        if (decoded != null) {
          embed = decoded.contains('<iframe')
              ? iframeFromHtmlString(decoded, baseUrl)
              : (decoded.trim().startsWith('http') ? decoded.trim() : null);
        }
      }
      if (embed != null) addMirror(label, embed);
    }

    // Pola link.
    for (final a in doc.querySelectorAll('.responsive-stream a, .mblink, .mirror-stream a')) {
      final href = a.attributes['href'];
      if (href == null || href.isEmpty || href == '#') continue;
      addMirror(cleanText(a.text), absoluteUrl(baseUrl, href));
    }

    final downloads = parseDownloadLinks(doc, baseUrl);
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
    final html = await _http.getHtml(baseUrl);
    final doc = parseHtml(html);
    final genres = <Genre>[];
    doc.querySelectorAll('.genre-list a, .genres a, .genre-filter a').forEach((a) {
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
    final html = await _http.getHtml('$baseUrl/jadwal');
    final doc = parseHtml(html);
    final days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    final result = <DaySchedule>[];
    for (final day in days) {
      final entries = <ScheduleEntry>[];
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
    // Hidoristream pakai list dengan class .rel, .col, .card
    doc.querySelectorAll('.rel, .rel1, .col-md-4, .col .rel, .lst, .card-anime').forEach((card) {
      final a = card.querySelector('a[href*="anime"], a[href*="/anime/"], h2 a, h3 a, .tt a');
      if (a == null) return;
      final href = a.attributes['href'];
      if (href == null) return;
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
    final html = await _http.getHtml(url);
    final doc = parseHtml(html);
    final list = <Anime>[];
    doc.querySelectorAll('.col, .col-md-4, .rel, .list-anime .item').forEach((card) {
      final a = card.querySelector('a');
      final title = cleanText(card.querySelector('h2, h3, .title, .tt')?.text);
      final href = a?.attributes['href'];
      final thumb = card.querySelector('img')?.attributes['src'];
      if (href == null || title.isEmpty) return;
      final slug = href.split('/').where((s) => s.isNotEmpty).lastOrNull;
      list.add(Anime(
        id: Anime.makeId(source, slug ?? href),
        source: source,
        title: title,
        slug: slug ?? '',
        url: href,
        cover: thumb,
      ));
    });
    return list;
  }
}
