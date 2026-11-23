/// Scraper untuk Lendrive (lendrive.web.id).
///
/// Lendrive memakai tema WordPress "Themesia":
///  - Daftar anime : `article.bs` -> `a[itemprop="url"]`, `img.ts-post-image`
///  - Katalog      : /anime/?status=...&type=&order=update (paginated /anime/page/N/)
///  - Detail       : `.infox` (info + genre), `.eplister` (daftar episode)
///  - Episode      : `.soraurlx` (blok resolusi + link file-host)
///
/// Lendrive fokus ke download MKV/MP4 720p/1080p HEVC, bukan streaming.
library;

import 'package:html/dom.dart' as dom;

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

  /// Katalog seri (bukan halaman home, yang isinya episode lepas).
  String _catalogUrl({String? status, int page = 1}) {
    final path = page <= 1 ? '$baseUrl/anime/' : '$baseUrl/anime/page/$page/';
    final filter = (status == null || status.isEmpty)
        ? 'status&type=&order=update'
        : 'status=$status&type=&order=update';
    return '$path?$filter';
  }

  @override
  Future<List<Anime>> getLatest({int page = 1}) async {
    return _parseCards(_catalogUrl(page: page));
  }

  @override
  Future<List<Anime>> getOngoing({int page = 1}) async {
    return _parseCards(_catalogUrl(status: 'ongoing', page: page));
  }

  @override
  Future<List<Anime>> getCompleted({int page = 1}) async {
    return _parseCards(_catalogUrl(status: 'completed', page: page));
  }

  @override
  Future<Anime> getDetail(Anime anime) async {
    final doc = parseHtml(await _http.getHtml(anime.url));
    final info = doc.querySelector('.infox') ??
        doc.querySelector('.anime-info') ??
        doc.querySelector('.bixbox.animefull');

    String textOf(String selector) =>
        cleanText(doc.querySelector(selector)?.text);

    String? status, type, studio, release, season, duration;
    int? totalEps;
    double? score;

    void readInfo(String raw) {
      final idx = raw.indexOf(':');
      if (idx <= 0) return;
      final label = raw.substring(0, idx).trim().toLowerCase();
      final value = raw.substring(idx + 1).trim();
      if (value.isEmpty || value == '?' || value == '-') return;
      switch (label) {
        case 'status':
          status = value;
        case 'type':
          type = value;
        case 'studio':
          studio = value;
        case 'released':
        case 'release':
        case 'released on':
          release = value;
        case 'season':
          season = value;
        case 'duration':
          duration = value;
        case 'total episode':
        case 'episodes':
          totalEps = int.tryParse(RegExp(r'\d+').stringMatch(value) ?? '');
        case 'score':
          score = double.tryParse(RegExp(r'[\d.]+').stringMatch(value) ?? '');
      }
    }

    if (info != null) {
      for (final span in info.querySelectorAll('.spe span, .info-content span')) {
        readInfo(cleanText(span.text));
      }
    }

    // Rating tampil sebagai "Rating 8.73".
    if (score == null) {
      final ratingText = textOf('.rating strong, .rating');
      final m = RegExp(r'([\d.]+)').firstMatch(ratingText);
      score = double.tryParse(m?.group(1) ?? '');
    }

    final genres = <Genre>[];
    for (final a in (info ?? doc).querySelectorAll('.genxed a[href]')) {
      final name = cleanText(a.text);
      final href = a.attributes['href'];
      if (name.isEmpty || href == null) continue;
      if (genres.any((g) => g.name == name)) continue;
      genres.add(Genre(
        name: name,
        slug: Uri.tryParse(href)?.pathSegments.where((s) => s.isNotEmpty).last,
        url: href,
      ));
    }

    final synp = doc.querySelector('.synp .entry-content') ??
        doc.querySelector('.synp') ??
        doc.querySelector('.desc');
    var synopsis = '';
    if (synp != null) {
      final paras = synp
          .querySelectorAll('p')
          .map((p) => cleanText(p.text))
          .where((t) => t.isNotEmpty)
          .toList();
      synopsis = paras.isNotEmpty ? paras.join('\n\n') : cleanText(synp.text);
    }

    // Daftar episode: .eplister ul li a dengan .epl-num / .epl-title / .epl-date.
    final episodes = <Episode>[];
    final seenEp = <String>{};
    for (final a in doc.querySelectorAll('.eplister a[href]')) {
      final href = a.attributes['href'];
      if (href == null || href.isEmpty || href == '#') continue;
      final url = absoluteUrl(baseUrl, href);
      if (url.isEmpty || !seenEp.add(url)) continue;

      final number = cleanText(a.querySelector('.epl-num')?.text);
      final rawTitle = cleanText(a.querySelector('.epl-title')?.text);
      final date = cleanText(a.querySelector('.epl-date')?.text);
      final title = rawTitle.isNotEmpty
          ? _episodeTitle(cleanTitle(rawTitle))
          : 'Episode $number';

      episodes.add(Episode(
        id: '${anime.id}::${url.hashCode}',
        animeId: anime.id,
        source: source,
        title: title.isEmpty ? 'Episode $number' : title,
        slug: Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull,
        url: url,
        number: number.isEmpty ? _numberFromTitle(title) : number,
        releasedAt: date.isEmpty ? null : date,
      ));
    }

    final title = textOf('h1.entry-title');
    final altTitle = textOf('.infox .alter, .alter');
    final cover = doc.querySelector('.thumbook img, .thumb img')?.attributes['src'] ??
        anime.cover;
    final banner = doc
            .querySelector('.bigcontent .thumbnail img, .entry-content .thumbnail img, .banner img')
            ?.attributes['src'] ??
        anime.banner;

    return anime.copyWith(
      title: title.isNotEmpty ? title : anime.title,
      altTitle: altTitle.isNotEmpty ? altTitle : anime.altTitle,
      cover: cover,
      banner: banner,
      status: status ?? anime.status,
      type: type ?? anime.type,
      studio: studio ?? anime.studio,
      releaseDate: release ?? anime.releaseDate,
      season: season ?? anime.season,
      totalEpisodes: totalEps ?? anime.totalEpisodes,
      score: score ?? anime.score,
      genres: genres.isNotEmpty ? genres : anime.genres,
      synopsis: synopsis.isNotEmpty ? synopsis : anime.synopsis,
      episodes: episodes,
      episodeCount: episodes.isNotEmpty ? episodes.length : anime.episodeCount,
    );
  }

  @override
  Future<Episode> getEpisodeDetail(Episode episode) async {
    final doc = parseHtml(await _http.getHtml(episode.url));

    final downloads = <DownloadOption>[];
    final seen = <String>{};

    void add(String? href, String qualityLabel, String hostName) {
      if (href == null) return;
      final raw = href.trim();
      if (raw.isEmpty || raw == '#' || raw.startsWith('javascript:')) return;
      final url = absoluteUrl(baseUrl, raw);
      if (url.isEmpty || !seen.add(url)) return;
      final host = detectServer(url);
      final label = [
        if (qualityLabel.isNotEmpty) qualityLabel,
        if (hostName.isNotEmpty) hostName,
      ].join(' • ');
      downloads.add(DownloadOption(
        label: label.isEmpty ? (host == 'other' ? 'Download' : host) : label,
        quality: VideoQuality.fromLabel(qualityLabel) ??
            VideoQuality.fromLabel(label),
        url: url,
        host: host != 'other' ? host : (hostName.isNotEmpty ? hostName.toLowerCase() : null),
      ));
    }

    // Blok resolusi: <div class="soraurlx"><strong>720p | 155mb</strong> <a>Acefile</a>...
    for (final box in doc.querySelectorAll('.soraurlx')) {
      final rawLabel = cleanText(box.querySelector('strong, b, h4, h3')?.text);
      final quality = rawLabel.split('|').first.trim();
      for (final a in box.querySelectorAll('a[href]')) {
        add(a.attributes['href'], quality, cleanText(a.text));
      }
    }

    // Tabel/daftar download generik sebagai pelengkap.
    for (final d in parseDownloadLinks(doc, baseUrl)) {
      if (seen.add(d.url)) downloads.add(d);
    }

    const qualityOrder = {
      '1080p hevc': 5,
      '1080p': 4,
      '720p': 3,
      '480p': 2,
      '360p': 1,
    };
    int rank(DownloadOption d) {
      final q = (d.quality?.label ?? d.label).toLowerCase();
      for (final e in qualityOrder.entries) {
        if (q.contains(e.key)) return e.value;
      }
      return 0;
    }

    downloads.sort((a, b) => rank(b).compareTo(rank(a)));

    return episode.copyWith(
      downloads: downloads,
      // Lendrive tidak menyediakan player streaming — hanya download.
      mirrors: const [],
    );
  }

  @override
  Future<String?> resolveMirrorEmbed(StreamMirror mirror) async =>
      mirror.embedUrl.isEmpty ? null : mirror.embedUrl;

  @override
  Future<List<Anime>> search(String query) async {
    return _parseCards('$baseUrl/?s=${Uri.encodeQueryComponent(query)}');
  }

  @override
  Future<List<Genre>> getGenres() async {
    final doc = parseHtml(await _http.getHtml('$baseUrl/genres/'));
    final genres = <Genre>[];
    const skip = {'genres', 'genre', 'home', 'anime', 'ongoing', 'completed'};
    for (final a in doc.querySelectorAll('.taxindex a, a[href*="/genres/"]')) {
      final href = a.attributes['href'] ?? '';
      if (href.contains('/feed') || href.contains('/page/')) continue;
      // Nama ada di <span class="name">, jumlah judul di <span class="count">.
      final name = cleanText(
        (a.querySelector('.name')?.text ?? a.text)
            .replaceAll(RegExp(r'\s+\d+$'), ''),
      );
      final slug = Uri.tryParse(href)?.pathSegments.where((s) => s.isNotEmpty).last;
      if (name.isEmpty || slug == null || skip.contains(slug.toLowerCase())) continue;
      if (genres.any((g) => g.name == name)) continue;
      genres.add(Genre(name: name, slug: slug, url: href));
    }
    return genres;
  }

  @override
  Future<List<Anime>> getByGenre(Genre genre, {int page = 1}) async {
    final url = genre.url;
    if (url == null || url.isEmpty) return [];
    final pageUrl = page <= 1 ? url : '${url.replaceAll(RegExp(r'/+$'), '')}page/$page/';
    return _parseCards(pageUrl);
  }

  @override
  Future<List<DaySchedule>> getSchedule() async {
    // Lendrive menaruh jadwal sebagai dropdown di beranda; tidak ada halaman
    // jadwal terpisah yang stabil, jadi dikosongkan.
    return const [];
  }

  @override
  Future<String?> resolveDirectUrl(String embedUrl) => resolveDirectFromEmbed(embedUrl);

  Future<List<Anime>> _parseCards(String url) async {
    final doc = parseHtml(await _http.getHtml(url));
    final out = <Anime>[];
    final seen = <String>{};
    for (final card in _cards(doc)) {
      final anime = _animeFromCard(card);
      if (anime == null || !seen.add(anime.url)) continue;
      out.add(anime);
    }
    return out;
  }

  Iterable<dom.Element> _cards(dom.Document doc) {
    final articles = doc.querySelectorAll('article.bs');
    if (articles.isNotEmpty) return articles;
    return doc.querySelectorAll('.listupd .bs, .bsx');
  }

  Anime? _animeFromCard(dom.Element card) {
    final anchor = card.querySelector('a[itemprop="url"]') ??
        card.querySelector('a.tip') ??
        card.querySelector('.tt a[href]') ??
        card.querySelector('a[href]');
    final href = anchor?.attributes['href'];
    if (href == null || href.isEmpty || href == '#') return null;
    final url = absoluteUrl(baseUrl, href);

    final rawTitle = anchor?.attributes['title'] ??
        card.querySelector('h2[itemprop="headline"]')?.text ??
        card.querySelector('h2')?.text ??
        card.querySelector('.tt')?.text ??
        anchor?.text ??
        '';
    final title = _seriesTitle(cleanText(rawTitle));
    if (title.isEmpty) return null;

    final img = card.querySelector('img.ts-post-image') ??
        card.querySelector('img[itemprop="image"]') ??
        card.querySelector('img');
    final cover = img?.attributes['src'] ?? img?.attributes['data-src'];

    final type = cleanText(card.querySelector('.typez')?.text);
    final badge = cleanText(card.querySelector('.bt .epx')?.text).toLowerCase();
    String? status;
    if (badge.contains('ongoing')) status = 'Ongoing';
    if (badge.contains('completed')) status = 'Completed';

    final slug = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? url;

    return Anime(
      id: Anime.makeId(source, slug),
      source: source,
      title: title,
      slug: slug,
      url: url,
      cover: cover,
      type: type.isEmpty ? null : type,
      status: status,
    );
  }

  /// Buang embel-embel judul post episode ("– Ep 07 (Dual subs) x265/HEVC ...").
  String _seriesTitle(String input) {
    var t = input;
    t = t.replaceAll(
      RegExp(r'\s*[–\-—]\s*Ep(?:isode)?\s*\d+.*$', caseSensitive: false),
      '',
    );
    t = t.replaceAll(
      RegExp(r'\s*[–\-—]\s*\(?Batch\b.*$', caseSensitive: false),
      '',
    );
    t = t.replaceAll(
      RegExp(r'\s+\(?(Dual\s*subs?|x265\s*/\s*HEVC|Subtitle\s+Indonesia)\b.*$',
          caseSensitive: false),
      '',
    );
    return t.trim();
  }

  /// Rapikan judul episode: buang ekor "x265/HEVC Subtitle Indonesia & English".
  String _episodeTitle(String input) {
    var t = input;
    t = t.replaceAll(
      RegExp(r'\s*[–\-—]?\s*x265\s*/\s*HEVC.*$', caseSensitive: false),
      '',
    );
    t = t.replaceAll(
      RegExp(r'\s*[–\-—]?\s*Subtitle\s+(?:Indonesia|English).*$', caseSensitive: false),
      '',
    );
    t = t.replaceAll(RegExp(r'[\s–\-—]+$'), '');
    return t.trim();
  }

  String? _numberFromTitle(String title) {
    final m = RegExp(r'Ep(?:isode)?\s*(\d+(?:\.\d+)?)', caseSensitive: false)
        .firstMatch(title);
    return m?.group(1);
  }
}
