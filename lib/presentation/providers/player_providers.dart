/// Provider untuk player state: current anime, episode, mirror, quality, position.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/models/anime.dart';
import '../../data/models/episode.dart';
import '../../data/repositories/anime_repository.dart';

class PlayerState {
  final Anime? anime;
  final Episode? episode;
  final StreamMirror? mirror;
  final VideoQuality quality;
  final double playbackSpeed;
  final Duration position;
  final Duration duration;

  const PlayerState({
    this.anime,
    this.episode,
    this.mirror,
    this.quality = VideoQuality.q720,
    this.playbackSpeed = 1.0,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  PlayerState copyWith({
    Anime? anime,
    Episode? episode,
    StreamMirror? mirror,
    VideoQuality? quality,
    double? playbackSpeed,
    Duration? position,
    Duration? duration,
  }) {
    return PlayerState(
      anime: anime ?? this.anime,
      episode: episode ?? this.episode,
      mirror: mirror ?? this.mirror,
      quality: quality ?? this.quality,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }
}

class PlayerNotifier extends StateNotifier<PlayerState> {
  PlayerNotifier() : super(const PlayerState());

  void setAnime(Anime anime) => state = state.copyWith(anime: anime);
  void setEpisode(Episode ep) => state = state.copyWith(episode: ep);
  void setMirror(StreamMirror mirror) => state = state.copyWith(mirror: mirror);
  void setQuality(VideoQuality q) => state = state.copyWith(quality: q);
  void setSpeed(double s) => state = state.copyWith(playbackSpeed: s);
  void setPosition(Duration p) => state = state.copyWith(position: p);
  void setDuration(Duration d) => state = state.copyWith(duration: d);

  /// Resolve direct URL untuk mirror terpilih.
  Future<String?> resolveDirectUrl() async {
    final m = state.mirror;
    if (m == null) return null;
    // Kalau ada direct URL, pakai langsung
    if (m.directUrl != null) return m.directUrl;
    // Cari download option yang match quality
    final dl = m.downloads
        .where((d) => d.quality == state.quality)
        .firstOrNull;
    if (dl != null) return dl.url;
    // Resolve embed URL via scraper
    final ep = state.episode;
    if (ep == null) return null;
    return animeRepository.resolveDirectUrl(ep.source, m.embedUrl);
  }

  void reset() => state = const PlayerState();
}

final playerProvider =
    StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  return PlayerNotifier();
});
