/// Model Anime — representasi anime dari salah satu sumber.
library;

import 'package:equatable/equatable.dart';

import '../../core/constants.dart';
import 'episode.dart';
import 'genre.dart';

class Anime extends Equatable {
  /// ID internal: gabungan source + slug unik
  final String id;
  final SourceId source;
  final String title;
  final String? altTitle;
  final String slug;
  final String url;

  /// Cover image URL
  final String? cover;
  /// Banner / thumbnail besar (untuk hero di detail page)
  final String? banner;

  /// Status: Ongoing, Completed, dll
  final String? status;
  final String? type;
  final int? totalEpisodes;
  final int? episodeCount;
  final double? score;
  final String? studio;
  final String? releaseDate;
  final String? season;

  final List<Genre> genres;
  final String? synopsis;
  final List<String> producers;

  /// Episode list — hanya diisi saat user buka detail page
  final List<Episode> episodes;

  const Anime({
    required this.id,
    required this.source,
    required this.title,
    this.altTitle,
    required this.slug,
    required this.url,
    this.cover,
    this.banner,
    this.status,
    this.type,
    this.totalEpisodes,
    this.episodeCount,
    this.score,
    this.studio,
    this.releaseDate,
    this.season,
    this.genres = const [],
    this.synopsis,
    this.producers = const [],
    this.episodes = const [],
  });

  Anime copyWith({
    String? id,
    SourceId? source,
    String? title,
    String? altTitle,
    String? slug,
    String? url,
    String? cover,
    String? banner,
    String? status,
    String? type,
    int? totalEpisodes,
    int? episodeCount,
    double? score,
    String? studio,
    String? releaseDate,
    String? season,
    List<Genre>? genres,
    String? synopsis,
    List<String>? producers,
    List<Episode>? episodes,
  }) {
    return Anime(
      id: id ?? this.id,
      source: source ?? this.source,
      title: title ?? this.title,
      altTitle: altTitle ?? this.altTitle,
      slug: slug ?? this.slug,
      url: url ?? this.url,
      cover: cover ?? this.cover,
      banner: banner ?? this.banner,
      status: status ?? this.status,
      type: type ?? this.type,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      episodeCount: episodeCount ?? this.episodeCount,
      score: score ?? this.score,
      studio: studio ?? this.studio,
      releaseDate: releaseDate ?? this.releaseDate,
      season: season ?? this.season,
      genres: genres ?? this.genres,
      synopsis: synopsis ?? this.synopsis,
      producers: producers ?? this.producers,
      episodes: episodes ?? this.episodes,
    );
  }

  /// ID unik untuk storage (favorites/history)
  static String makeId(SourceId source, String slug) => '${source.id}::$slug';

  @override
  List<Object?> get props => [id];

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.name,
        'title': title,
        'altTitle': altTitle,
        'slug': slug,
        'url': url,
        'cover': cover,
        'banner': banner,
        'status': status,
        'type': type,
        'totalEpisodes': totalEpisodes,
        'episodeCount': episodeCount,
        'score': score,
        'studio': studio,
        'releaseDate': releaseDate,
        'season': season,
        'genres': genres.map((g) => g.toJson()).toList(),
        'synopsis': synopsis,
        'producers': producers,
      };

  factory Anime.fromJson(Map<String, dynamic> json) {
    return Anime(
      id: json['id'] as String,
      source: SourceId.values.byName(json['source'] as String),
      title: json['title'] as String,
      altTitle: json['altTitle'] as String?,
      slug: json['slug'] as String,
      url: json['url'] as String,
      cover: json['cover'] as String?,
      banner: json['banner'] as String?,
      status: json['status'] as String?,
      type: json['type'] as String?,
      totalEpisodes: json['totalEpisodes'] as int?,
      episodeCount: json['episodeCount'] as int?,
      score: (json['score'] as num?)?.toDouble(),
      studio: json['studio'] as String?,
      releaseDate: json['releaseDate'] as String?,
      season: json['season'] as String?,
      genres: ((json['genres'] as List?) ?? [])
          .map((e) => Genre.fromJson(e as Map<String, dynamic>))
          .toList(),
      synopsis: json['synopsis'] as String?,
      producers: (json['producers'] as List?)?.cast<String>() ?? const [],
    );
  }
}
