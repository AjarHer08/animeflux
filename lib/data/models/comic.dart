/// Model komik (Komiku, Komikstation, Kiryuu).
library;

import 'package:equatable/equatable.dart';

import '../../core/theme/app_theme.dart' show sharedPreferencesInstance;

enum ComicSourceId { komikstation, kiryuu, komiku }

extension ComicSourceIdX on ComicSourceId {
  String get label {
    switch (this) {
      case ComicSourceId.komikstation:
        return 'Komikstation';
      case ComicSourceId.kiryuu:
        return 'Kiryuu';
      case ComicSourceId.komiku:
        return 'Komiku';
    }
  }

  String get defaultBaseUrl {
    switch (this) {
      case ComicSourceId.komikstation:
        return 'https://komikstation.org';
      case ComicSourceId.kiryuu:
        return 'https://v7.kiryuu.to';
      case ComicSourceId.komiku:
        return 'https://komiku.org';
    }
  }

  String get _prefKey => 'comic_base_$name';

  /// Domain situs komik sering pindah (mis. v7.kiryuu.to -> v8...). Bisa
  /// diubah pengguna dari Pengaturan tanpa build ulang.
  String get baseUrl {
    final v = sharedPreferencesInstance.getString(_prefKey);
    if (v != null && v.startsWith('http')) {
      return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
    }
    return defaultBaseUrl;
  }

  Future<void> setBaseUrl(String? url) async {
    if (url == null || url.trim().isEmpty) {
      await sharedPreferencesInstance.remove(_prefKey);
    } else {
      await sharedPreferencesInstance.setString(_prefKey, url.trim());
    }
  }
}

class ComicChapter extends Equatable {
  final String title;
  final String url;
  final String? number;
  final String? date;

  const ComicChapter({required this.title, required this.url, this.number, this.date});

  @override
  List<Object?> get props => [url];
}

class Comic extends Equatable {
  final String id;
  final ComicSourceId source;
  final String title;
  final String slug;
  final String url;
  final String? cover;
  final String? status;
  final String? type;
  final String? author;
  final double? rating;
  final String? latestChapter;
  final String? synopsis;
  final List<String> genres;

  /// Urutan: terbaru dulu.
  final List<ComicChapter> chapters;

  const Comic({
    required this.id,
    required this.source,
    required this.title,
    required this.slug,
    required this.url,
    this.cover,
    this.status,
    this.type,
    this.author,
    this.rating,
    this.latestChapter,
    this.synopsis,
    this.genres = const [],
    this.chapters = const [],
  });

  static String makeId(ComicSourceId s, String slug) => '${s.name}::$slug';

  Comic copyWith({
    String? title,
    String? cover,
    String? status,
    String? type,
    String? author,
    double? rating,
    String? latestChapter,
    String? synopsis,
    List<String>? genres,
    List<ComicChapter>? chapters,
  }) {
    return Comic(
      id: id,
      source: source,
      title: title ?? this.title,
      slug: slug,
      url: url,
      cover: cover ?? this.cover,
      status: status ?? this.status,
      type: type ?? this.type,
      author: author ?? this.author,
      rating: rating ?? this.rating,
      latestChapter: latestChapter ?? this.latestChapter,
      synopsis: synopsis ?? this.synopsis,
      genres: genres ?? this.genres,
      chapters: chapters ?? this.chapters,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.name,
        'title': title,
        'slug': slug,
        'url': url,
        'cover': cover,
        'type': type,
        'latestChapter': latestChapter,
      };

  factory Comic.fromJson(Map<String, dynamic> j) => Comic(
        id: j['id'] as String,
        source: ComicSourceId.values.byName(j['source'] as String),
        title: j['title'] as String,
        slug: j['slug'] as String,
        url: j['url'] as String,
        cover: j['cover'] as String?,
        type: j['type'] as String?,
        latestChapter: j['latestChapter'] as String?,
      );

  @override
  List<Object?> get props => [id];
}
