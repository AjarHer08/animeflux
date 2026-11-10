/// Model Episode — satu episode dari sebuah anime.
library;

import 'package:equatable/equatable.dart';

import '../../core/constants.dart';

class Episode extends Equatable {
  /// ID internal: animeId + episodeId
  final String id;
  final String animeId;
  final SourceId source;
  final String title;
  final String? slug;
  final String url;
  final String? number;
  final String? releasedAt;
  /// Mirror streaming — diisi saat user buka player page
  final List<StreamMirror> mirrors;
  /// Link download untuk episode ini (semua resolusi/host) — diisi saat
  /// detail episode dimuat. Terpisah dari mirror supaya tombol download
  /// tetap muncul walaupun episode tidak punya mirror streaming.
  final List<DownloadOption> downloads;

  const Episode({
    required this.id,
    required this.animeId,
    required this.source,
    required this.title,
    this.slug,
    required this.url,
    this.number,
    this.releasedAt,
    this.mirrors = const [],
    this.downloads = const [],
  });

  Episode copyWith({
    String? id,
    String? animeId,
    SourceId? source,
    String? title,
    String? slug,
    String? url,
    String? number,
    String? releasedAt,
    List<StreamMirror>? mirrors,
    List<DownloadOption>? downloads,
  }) {
    return Episode(
      id: id ?? this.id,
      animeId: animeId ?? this.animeId,
      source: source ?? this.source,
      title: title ?? this.title,
      slug: slug ?? this.slug,
      url: url ?? this.url,
      number: number ?? this.number,
      releasedAt: releasedAt ?? this.releasedAt,
      mirrors: mirrors ?? this.mirrors,
      downloads: downloads ?? this.downloads,
    );
  }

  @override
  List<Object?> get props => [id];
}

/// Satu mirror streaming — biasanya 1 episode punya beberapa mirror (server berbeda).
class StreamMirror extends Equatable {
  final String id;
  final String label; // e.g. "Mirror 1", "Server Acefile", "Mp4Upload"
  final String server; // e.g. "acefile", "hxfile", "mp4upload", "gdrive"
  final String embedUrl; // URL iframe player
  /// Didapat setelah resolve embed → bisa langsung di-play
  final String? directUrl;
  final List<DownloadOption> downloads;
  /// Data tambahan untuk resolve embed secara lazy (mis. `data-content`
  /// base64 milik Otakudesu). Kalau terisi, [embedUrl] boleh kosong.
  final String? payload;

  const StreamMirror({
    required this.id,
    required this.label,
    required this.server,
    required this.embedUrl,
    this.directUrl,
    this.downloads = const [],
    this.payload,
  });

  StreamMirror copyWith({
    String? id,
    String? label,
    String? server,
    String? embedUrl,
    String? directUrl,
    List<DownloadOption>? downloads,
    String? payload,
  }) {
    return StreamMirror(
      id: id ?? this.id,
      label: label ?? this.label,
      server: server ?? this.server,
      embedUrl: embedUrl ?? this.embedUrl,
      directUrl: directUrl ?? this.directUrl,
      downloads: downloads ?? this.downloads,
      payload: payload ?? this.payload,
    );
  }

  @override
  List<Object?> get props => [id, embedUrl, payload];
}

/// Opsi download untuk 1 mirror — bisa multiple resolution.
class DownloadOption extends Equatable {
  final String label; // "720p", "1080p", "MKV 720p"
  final VideoQuality? quality;
  final String url;
  final String? host; // "acefile", "hxfile", "gdrive", "mir"

  const DownloadOption({
    required this.label,
    required this.url,
    this.quality,
    this.host,
  });

  @override
  List<Object?> get props => [url];
}
