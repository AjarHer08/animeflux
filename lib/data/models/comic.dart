/// Model komik (Komiku, Komikstation, Kiryuu).
library;

import 'package:equatable/equatable.dart';

import '../../core/theme/app_theme.dart' show sharedPreferencesInstance;

enum ComicSourceId { komikstation, kiryuu, komiku }

/// Kategori tipe komik per sumber: Manga (Jepang), Manhwa (Korea), Manhua (Tiongkok).
enum ComicCategory { all, manga, manhwa, manhua }

extension ComicCategoryX on ComicCategory {
  String get label {
    switch (this) {
      case ComicCategory.all:
        return 'Semua';
      case ComicCategory.manga:
        return 'Manga';
      case ComicCategory.manhwa:
        return 'Manhwa';
      case ComicCategory.manhua:
        return 'Manhua';
    }
  }

  /// Nilai untuk parameter URL (kosong = tanpa filter).
  String get slug => this == ComicCategory.all ? '' : name;
}

/// Urutan daftar komik.
enum ComicOrder { latest, popular, az, added }

extension ComicOrderX on ComicOrder {
  String get label {
    switch (this) {
      case ComicOrder.latest:
        return 'Update terbaru';
      case ComicOrder.popular:
        return 'Populer';
      case ComicOrder.az:
        return 'A-Z';
      case ComicOrder.added:
        return 'Baru ditambahkan';
    }
  }
}

/// Status terbit komik.
enum ComicStatusFilter { all, ongoing, completed }

extension ComicStatusFilterX on ComicStatusFilter {
  String get label {
    switch (this) {
      case ComicStatusFilter.all:
        return 'Semua';
      case ComicStatusFilter.ongoing:
        return 'Berjalan';
      case ComicStatusFilter.completed:
        return 'Tamat';
    }
  }
}

class ComicGenre extends Equatable {
  final String slug;
  final String label;
  const ComicGenre(this.slug, this.label);

  @override
  List<Object?> get props => [slug];
}

/// Gabungan semua filter daftar komik: tipe + status + genre + urutan.
class ComicFilter extends Equatable {
  final ComicCategory category;
  final ComicStatusFilter status;
  final ComicGenre? genre;
  final ComicOrder order;

  const ComicFilter({
    this.category = ComicCategory.all,
    this.status = ComicStatusFilter.all,
    this.genre,
    this.order = ComicOrder.latest,
  });

  bool get isDefault =>
      category == ComicCategory.all && status == ComicStatusFilter.all && genre == null;

  ComicFilter copyWith({
    ComicCategory? category,
    ComicStatusFilter? status,
    ComicOrder? order,
    ComicGenre? genre,
    bool clearGenre = false,
  }) =>
      ComicFilter(
        category: category ?? this.category,
        status: status ?? this.status,
        order: order ?? this.order,
        genre: clearGenre ? null : (genre ?? this.genre),
      );

  @override
  List<Object?> get props => [category, status, genre, order];
}

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
