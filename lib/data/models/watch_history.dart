/// Model WatchHistory — entri riwayat tonton user.
library;

import 'package:equatable/equatable.dart';

import '../../core/constants.dart';

class WatchHistoryEntry extends Equatable {
  final String animeId;
  final String animeTitle;
  final String? animeCover;
  final SourceId source;
  final String episodeId;
  final String episodeTitle;
  final String episodeUrl;
  final Duration position;
  final Duration duration;
  final DateTime watchedAt;

  const WatchHistoryEntry({
    required this.animeId,
    required this.animeTitle,
    this.animeCover,
    required this.source,
    required this.episodeId,
    required this.episodeTitle,
    required this.episodeUrl,
    required this.position,
    required this.duration,
    required this.watchedAt,
  });

  double get progress =>
      duration.inSeconds > 0 ? position.inSeconds / duration.inSeconds : 0;

  WatchHistoryEntry copyWith({
    String? animeId,
    String? animeTitle,
    String? animeCover,
    SourceId? source,
    String? episodeId,
    String? episodeTitle,
    String? episodeUrl,
    Duration? position,
    Duration? duration,
    DateTime? watchedAt,
  }) {
    return WatchHistoryEntry(
      animeId: animeId ?? this.animeId,
      animeTitle: animeTitle ?? this.animeTitle,
      animeCover: animeCover ?? this.animeCover,
      source: source ?? this.source,
      episodeId: episodeId ?? this.episodeId,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      episodeUrl: episodeUrl ?? this.episodeUrl,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      watchedAt: watchedAt ?? this.watchedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'animeId': animeId,
        'animeTitle': animeTitle,
        'animeCover': animeCover,
        'source': source.name,
        'episodeId': episodeId,
        'episodeTitle': episodeTitle,
        'episodeUrl': episodeUrl,
        'position': position.inSeconds,
        'duration': duration.inSeconds,
        'watchedAt': watchedAt.toIso8601String(),
      };

  factory WatchHistoryEntry.fromJson(Map<String, dynamic> json) {
    return WatchHistoryEntry(
      animeId: json['animeId'] as String,
      animeTitle: json['animeTitle'] as String,
      animeCover: json['animeCover'] as String?,
      source: SourceId.values.byName(json['source'] as String),
      episodeId: json['episodeId'] as String,
      episodeTitle: json['episodeTitle'] as String,
      episodeUrl: json['episodeUrl'] as String,
      position: Duration(seconds: (json['position'] as num?)?.toInt() ?? 0),
      duration: Duration(seconds: (json['duration'] as num?)?.toInt() ?? 0),
      watchedAt: DateTime.parse(json['watchedAt'] as String),
    );
  }

  @override
  List<Object?> get props => [episodeId];
}
