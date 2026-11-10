/// Anime repository — fasad untuk 3 scraper, jalan paralel.
library;

import 'dart:async';

import '../../core/constants.dart';
import '../../core/utils/logger.dart';
import '../models/anime.dart';
import '../models/episode.dart';
import '../models/genre.dart';
import '../models/schedule.dart';
import '../scrapers/base_scraper.dart';
import '../scrapers/hidoristream_scraper.dart';
import '../scrapers/lendrive_scraper.dart';
import '../scrapers/otakudesu_scraper.dart';

class AnimeRepository {
  AnimeRepository() {
    _scrapers = {
      SourceId.otakudesu: OtakudesuScraper(),
      SourceId.hidoristream: HidoristreamScraper(),
      SourceId.lendrive: LendriveScraper(),
    };
  }

  late final Map<SourceId, BaseScraper> _scrapers;

  BaseScraper scraperFor(SourceId id) => _scrapers[id]!;

  /// Home page dari semua sumber, jalan paralel.
  /// Setiap sumber gagal → tidak menggagalkan sumber lain.
  Future<List<Anime>> getLatestAll({int page = 1}) async {
    final results = await Future.wait(
      SourceId.values.map((s) => _safeCall(() => _scrapers[s]!.getLatest(page: page))),
    );
    return [for (final r in results) ...r];
  }

  /// Latest hanya dari satu sumber
  ///
  /// Untuk panggilan satu sumber, error DILEMPAR (bukan ditelan) supaya UI
  /// bisa menampilkan pesan + tombol coba lagi, bukan daftar kosong misterius.
  Future<List<Anime>> getLatest(SourceId source, {int page = 1}) {
    return _call(source, 'getLatest', () => _scrapers[source]!.getLatest(page: page));
  }

  Future<List<Anime>> getOngoing(SourceId source, {int page = 1}) {
    return _call(source, 'getOngoing', () => _scrapers[source]!.getOngoing(page: page));
  }

  Future<List<Anime>> getCompleted(SourceId source, {int page = 1}) {
    return _call(source, 'getCompleted', () => _scrapers[source]!.getCompleted(page: page));
  }

  Future<Anime> getDetail(SourceId source, Anime anime) {
    return _scrapers[source]!.getDetail(anime);
  }

  Future<Episode> getEpisodeDetail(SourceId source, Episode episode) {
    return _scrapers[source]!.getEpisodeDetail(episode);
  }

  /// Search paralel di semua sumber
  Future<List<Anime>> searchAll(String query) async {
    final results = await Future.wait(
      SourceId.values.map((s) => _safeCall(() => _scrapers[s]!.search(query))),
    );
    return [for (final r in results) ...r];
  }

  Future<List<Anime>> search(SourceId source, String query) {
    return _safeCall(() => _scrapers[source]!.search(query));
  }

  Future<List<Genre>> getGenres(SourceId source) {
    return _safeCall(() => _scrapers[source]!.getGenres());
  }

  Future<List<Anime>> getByGenre(SourceId source, Genre genre, {int page = 1}) {
    return _safeCall(() => _scrapers[source]!.getByGenre(genre, page: page));
  }

  Future<List<DaySchedule>> getSchedule(SourceId source) {
    return _safeCall(() => _scrapers[source]!.getSchedule());
  }

  Future<String?> resolveDirectUrl(SourceId source, String embedUrl) {
    return _scrapers[source]!.resolveDirectUrl(embedUrl);
  }

  Future<String?> resolveMirrorEmbed(SourceId source, StreamMirror mirror) {
    return _scrapers[source]!.resolveMirrorEmbed(mirror);
  }

  /// Wrapper untuk agregasi multi-sumber: gagal 1 sumber -> [] (tapi di-log).
  Future<List<T>> _safeCall<T>(Future<List<T>> Function() action) async {
    try {
      return await action();
    } catch (e) {
      logger.w('Scraper gagal (diabaikan di mode multi-sumber): $e');
      return const [];
    }
  }

  /// Wrapper satu sumber: log lalu lempar ulang.
  Future<List<T>> _call<T>(
    SourceId source,
    String op,
    Future<List<T>> Function() action,
  ) async {
    try {
      return await action();
    } catch (e) {
      logger.e('${source.label}.$op gagal: $e');
      rethrow;
    }
  }
}

/// Singleton instance
final animeRepository = AnimeRepository();
