/// History repository — simpan ke SharedPreferences sebagai JSON.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../models/watch_history.dart';

class HistoryRepository {
  HistoryRepository(this._prefs);
  final SharedPreferences _prefs;

  List<WatchHistoryEntry> getAll() {
    final raw = _prefs.getStringList(StorageKeys.history) ?? [];
    return raw
        .map((e) => WatchHistoryEntry.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
  }

  /// Catat progres tonton. Kalau episode sama dengan entri terakhir, update.
  Future<void> record(WatchHistoryEntry entry) async {
    final items = getAll();
    items.removeWhere((e) =>
        e.animeId == entry.animeId && e.episodeId == entry.episodeId);
    items.insert(0, entry);
    // Batasi 200 entri
    if (items.length > 200) items.removeRange(200, items.length);
    await _prefs.setStringList(
      StorageKeys.history,
      items.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  /// Ambil posisi resume untuk episode tertentu
  Duration? getResumePosition(String animeId, String episodeId) {
    final items = getAll();
    final match = items
        .where((e) => e.animeId == animeId && e.episodeId == episodeId)
        .firstOrNull;
    return match?.position;
  }

  Future<void> remove(String animeId, String episodeId) async {
    final items = getAll()..removeWhere((e) =>
        e.animeId == animeId && e.episodeId == episodeId);
    await _prefs.setStringList(
      StorageKeys.history,
      items.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> clear() async {
    await _prefs.remove(StorageKeys.history);
  }
}
