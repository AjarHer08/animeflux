/// Scraper untuk Otakudesu.blog
///
/// Catatan: Otakudesu sering pakai Cloudflare WAF. Pastikan User-Agent yang
/// dipakai adalah browser desktop modern (sudah di-handle di HttpClient).
/// Selector HTML di bawah ini disusun berdasarkan struktur umum theme
/// WordPress yang dipakai situs anime Indonesia. Jika struktur berubah,
/// tinggal update selector-nya — logic utama tidak perlu diubah.
library;

import 'dart:convert';

import '../../core/constants.dart';
import '../../core/utils/html_utils.dart';
import '../../core/utils/http_client.dart';
import '../../core/utils/logger.dart';
import '../models/anime.dart';
import '../models/episode.dart';
import '../models/genre.dart';
import '../models/schedule.dart';
import 'base_scraper.dart';
import 'scraper_utils.dart';

class OtakudesuScraper implements BaseScraper {
  @override
  SourceId get source => SourceId.otakudesu;

  @override
  String get baseUrl => source.baseUrl;

  final _http = HttpClient.instance;

  @override
  Future<List<Anime>> getLatest({int page = 1}) async {
    final url = page <= 1 ? '$baseUrl/' : '$baseUrl/page/$page/';
    return _parseHomeGrid(url);
  }

  @override
  Future<List<Anime>> getOngoing({int page = 1}) async {
    final url = page <= 1
        ? '$baseUrl/ongoing-anime/'
        : '$baseUrl/ongoing-anime/page/$page/';
    return _parseAnimeList(url);
  }

  @override
  Future<List<Anime>> getCompleted({int page = 1}) async {
    final url = page <= 1
        ? '$baseUrl/completed-anime/'
        : '$baseUrl/completed-anime/page/$page/';
    return _parseAnimeList(url);
  }

  @override
  Future<Anime> getDetail(Anime anime) async {
    final html = await _http.getHtml(anime.url);
    final doc = parseHtml(html);

    // Metadata — selector fleksibel: cari di bagian "info anime"
    final infoBlock = doc.querySelector('.infozingle, .info, .anime-info, .anim-info');
    final infoRows = infoBlock?.querySelectorAll('p, li');
    String? status, type, totalEps, score, studio, release, season;
    final genres = <Genre>[];
    final producers = <String>[];

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
                slug: a.attributes['href']?.split('/').where((s) => s.isNotEmpty).last,
                url: a.attributes['href'],
              ));
            }
          });
        } else if (text.contains('status')) {
          status = value;
        } else if (text.contains('type')) {
          type = value;
        } else if (text.contains('total') && text.contains('eps')) {
          final m = RegExp(r'(\d+)').firstMatch(value);
          if (m != null) totalEps = m.group(1);
        } else if (text.contains('score') || text.contains('rating')) {
          final m = RegExp(r'(\d+\.?\d*)').firstMatch(value);
          if (m != null) score = m.group(1);
        } else if (text.contains('studio') || text.contains('produser')) {
          studio = value;
          producers.add(value);
        } else if (text.contains('released') || text.contains('rilis')) {
          release = value;
        } else if (text.contains('season')) {
          season = value;
        }
      }
    }

    // Sinopsis
    final synopsis = cleanText(
      doc.querySelector('.sinopc, .sinopsis, .desc, [class*="sinop"]')?.text,
    );

    // Banner
    final banner = attrFrom(doc, '.fotoanime img, .anime-thumb img, .thumb img', 'src');

    // Episode list — Otakudesu pakai <div class="episclick"> atau <ul class="episode-list">
    final episodes = <Episode>[];
    final epLinks = doc.querySelectorAll(
      '#episodeList a, .episodelist ul li a, .eplister a, .episode-list a, ul.lcp_catlist a',
    );
    for (final ep in epLinks) {
      final href = ep.attributes['href'];
      final title = cleanText(ep.text);
      if (href == null || title.isEmpty) continue;
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

    return anime.copyWith(
      status: status ?? anime.status,
      type: type ?? anime.type,
      totalEpisodes: totalEps != null ? int.tryParse(totalEps) : anime.totalEpisodes,
      score: score != null ? double.tryParse(score) : anime.score,
      studio: studio ?? anime.studio,
      releaseDate: release ?? anime.releaseDate,
      season: season ?? anime.season,
      genres: genres.isNotEmpty ? genres : anime.genres,
      producers: producers.isNotEmpty ? producers : anime.producers,
      synopsis: synopsis.isNotEmpty ? synopsis : anime.synopsis,
      banner: banner ?? anime.banner,
      episodes: episodes,
    );
  }

  @override
  Future<Episode> getEpisodeDetail(Episode episode) async {
    final html = await _http.getHtml(episode.url);
    final doc = parseHtml(html);
    final mirrors = <StreamMirror>[];
    final seenEmbeds = <String>{};

    void addMirror(String label, String embed, {String? payload}) {
      final key = payload ?? embed;
      if (key.isEmpty || !seenEmbeds.add(key)) return;
      mirrors.add(StreamMirror(
        id: '${episode.id}::${key.hashCode}',
        label: label.isEmpty ? 'Mirror ${mirrors.length + 1}' : label,
        server: embed.isNotEmpty ? detectServer(embed) : label.toLowerCase(),
        embedUrl: embed,
        payload: payload,
      ));
    }

    // 1) Player default halaman (selalu ada di HTML, tidak butuh AJAX).
    final defaultEmbed = firstIframeSrc(doc, baseUrl);
    if (defaultEmbed != null) addMirror('Default', defaultEmbed);

    // 2) Daftar mirror per kualitas: <div class="mirrorstream"><ul class="m720p">
    //    <li><a data-content="BASE64(json)">server</a>. URL asli baru didapat
    //    lewat AJAX (lihat resolveMirrorEmbed).
    for (final ul in doc.querySelectorAll('.mirrorstream ul')) {
      var quality = '';
      for (final c in ul.classes) {
        if (RegExp(r'^m\d+p$').hasMatch(c)) quality = c.substring(1);
      }
      for (final a in ul.querySelectorAll('a')) {
        final data = a.attributes['data-content'];
        if (data == null || data.isEmpty) continue;
        final name = cleanText(a.text);
        addMirror(quality.isEmpty ? name : '$name $quality', '', payload: data);
      }
    }

    // 3) Tema lain: <select> option (value = URL / base64 URL / base64 iframe).
    for (final opt in doc.querySelectorAll('select.mirrorstream option, select#mirrors option')) {
      final value = (opt.attributes['value'] ?? '').trim();
      if (value.isEmpty) continue;
      final label = cleanText(opt.text);
      String? embed;
      if (value.startsWith('http') || value.startsWith('//')) {
        embed = absoluteUrl(baseUrl, value);
      } else {
        final decoded = tryBase64Decode(value);
        if (decoded != null) {
          embed = decoded.contains('<iframe')
              ? iframeFromHtmlString(decoded, baseUrl)
              : (decoded.startsWith('http') ? decoded.trim() : null);
        }
      }
      if (embed != null) addMirror(label, embed);
    }

    // 4) Pola link langsung.
    for (final a in doc.querySelectorAll('.responsive-stream a, .stream-link, .mblink')) {
      final href = a.attributes['href'];
      if (href == null || href.isEmpty || href == '#') continue;
      addMirror(cleanText(a.text), absoluteUrl(baseUrl, href));
    }

    final downloads = parseDownloadLinks(doc, baseUrl);
    return episode.copyWith(mirrors: mirrors, downloads: downloads);
  }

  // Action AJAX admin-ajax.php milik tema Otakudesu. Nilai ini diambil dari
  // JS situs dan BISA BERUBAH kapan saja; kalau berubah, mirror AJAX gagal
  // di-resolve tapi mirror "Default" (iframe di HTML) tetap jalan.
  static const _kNonceAction = 'aa1208d27f29ca340c92c66d1926f13f';
  static const _kMirrorAction = '2a3505c93b0035d3f455df82bf976b84';

  @override
  Future<String?> resolveMirrorEmbed(StreamMirror mirror) async {
    final payload = mirror.payload;
    if (payload == null || payload.isEmpty) {
      return mirror.embedUrl.isEmpty ? null : mirror.embedUrl;
    }
    try {
      final decoded = tryBase64Decode(payload);
      if (decoded == null) return null;
      final params = Map<String, dynamic>.from(jsonDecode(decoded) as Map);
      final ajax = '$baseUrl/wp-admin/admin-ajax.php';

      final nonceRes = await _http.postForm(ajax, {'action': _kNonceAction});
      final nonce = (jsonDecode(nonceRes) as Map)['data']?.toString();
      if (nonce == null || nonce.isEmpty) return null;

      final res = await _http.postForm(ajax, {
        ...params,
        'nonce': nonce,
        'action': _kMirrorAction,
      });
      final data = (jsonDecode(res) as Map)['data']?.toString();
      final decodedHtml = tryBase64Decode(data);
      if (decodedHtml == null) return null;
      return iframeFromHtmlString(decodedHtml, baseUrl);
    } catch (e) {
      logger.w('Otakudesu resolveMirrorEmbed gagal: $e');
      return null;
    }
  }

  @override
  Future<List<Anime>> search(String query) async {
    final url = '$baseUrl/?s=${Uri.encodeQueryComponent(query)}&post_type=anime';
    return _parseHomeGrid(url);
  }

  @override
  Future<List<Genre>> getGenres() async {
    final html = await _http.getHtml(baseUrl);
    final doc = parseHtml(html);
    final genres = <Genre>[];
    doc.querySelectorAll('.genre-list a, .genres a, ul.menu-genre a, .genre-list li a').forEach((a) {
      final name = cleanText(a.text);
      final href = a.attributes['href'];
      if (name.isNotEmpty && href != null) {
        genres.add(Genre(
          name: name,
          slug: href.split('/').where((s) => s.isNotEmpty).lastOrNull,
          url: href,
        ));
      }
    });
    return genres;
  }

  @override
  Future<List<Anime>> getByGenre(Genre genre, {int page = 1}) async {
    if (genre.url == null) return [];
    final url = page <= 1 ? genre.url! : '${genre.url}/page/$page/';
    return _parseHomeGrid(url);
  }

  @override
  Future<List<DaySchedule>> getSchedule() async {
    final html = await _http.getHtml('$baseUrl/jadwal-rilis/');
    final doc = parseHtml(html);
    final days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    final result = <DaySchedule>[];
    for (final day in days) {
      final entries = <ScheduleEntry>[];
      // Otakudesu biasanya pakai <div class="kgjd3" id="Senin">
      final daySection = doc.querySelector('#$day, .day-$day, [data-day="$day"]');
      if (daySection == null) continue;
      daySection.querySelectorAll('a').forEach((a) {
        final href = a.attributes['href'];
        final title = cleanText(a.text);
        if (title.isNotEmpty && href != null) {
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

    // Pola umum: card di home dengan .detpost, .rel, .post-item, .col-img
    final cards = doc.querySelectorAll(
      '.detpost, .rel .rel1, .listpost .post, .col-img, .movie-item, article.post',
    );
    for (final card in cards) {
      final a = card.querySelector('a[href*="anime"], a[href*="episode"], h2 a, .thumb a, .tt a');
      if (a == null) continue;
      final href = a.attributes['href'];
      if (href == null) continue;
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
    }
    return list;
  }

  Future<List<Anime>> _parseAnimeList(String url) async {
    final html = await _http.getHtml(url);
    final doc = parseHtml(html);
    final list = <Anime>[];
    // Pola umum: list ongoing dengan .detpost
    doc.querySelectorAll('.detpost, .chbox, .list-anime .col-md-4, .rapi .col').forEach((card) {
      final a = card.querySelector('a');
      final thumb = card.querySelector('img')?.attributes['src'];
      final title = cleanText(card.querySelector('h2, .title, h3, .tt')?.text);
      final href = a?.attributes['href'];
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
