/// Base scraper — kontrak umum untuk semua sumber.
library;

import '../../core/constants.dart';
import '../../data/models/anime.dart';
import '../../data/models/episode.dart';
import '../../data/models/genre.dart';
import '../../data/models/schedule.dart';

abstract class BaseScraper {
  SourceId get source;
  String get baseUrl => source.baseUrl;

  /// Home page → list anime rilisan terbaru
  Future<List<Anime>> getLatest({int page = 1});

  /// Ongoing list
  Future<List<Anime>> getOngoing({int page = 1});

  /// Completed list
  Future<List<Anime>> getCompleted({int page = 1});

  /// Detail anime (with episodes list)
  Future<Anime> getDetail(Anime anime);

  /// Detail episode → list mirror & download options
  Future<Episode> getEpisodeDetail(Episode episode);

  /// Search by query
  Future<List<Anime>> search(String query);

  /// Genre list & anime by genre
  Future<List<Genre>> getGenres();
  Future<List<Anime>> getByGenre(Genre genre, {int page = 1});

  /// Jadwal rilisan per hari
  Future<List<DaySchedule>> getSchedule();

  /// Resolve mirror jadi URL embed final. Sebagian sumber (mis. Otakudesu)
  /// menyimpan mirror sebagai payload AJAX yang baru bisa di-resolve saat
  /// dipilih. Default: pakai [StreamMirror.embedUrl] apa adanya.
  Future<String?> resolveMirrorEmbed(StreamMirror mirror);

  /// Resolve embed URL jadi direct video URL (mp4 / m3u8).
  /// Override per-scraper karena tiap sumber pakai server berbeda.
  Future<String?> resolveDirectUrl(String embedUrl);
}
