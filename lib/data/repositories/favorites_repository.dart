/// Favorites repository — simpan ke SharedPreferences sebagai JSON.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../models/anime.dart';

class FavoritesRepository {
  FavoritesRepository(this._prefs);
  final SharedPreferences _prefs;

  List<Anime> getAll() {
    final raw = _prefs.getStringList(StorageKeys.favorites) ?? [];
    return raw.map((e) => Anime.fromJson(jsonDecode(e) as Map<String, dynamic>)).toList();
  }

  bool isFavorite(String animeId) {
    return getAll().any((a) => a.id == animeId);
  }

  Future<void> toggle(Anime anime) async {
    final items = getAll();
    if (items.any((a) => a.id == anime.id)) {
      items.removeWhere((a) => a.id == anime.id);
    } else {
      items.insert(0, anime);
    }
    await _prefs.setStringList(
      StorageKeys.favorites,
      items.map((a) => jsonEncode(a.toJson())).toList(),
    );
  }

  Future<void> remove(String animeId) async {
    final items = getAll()..removeWhere((a) => a.id == animeId);
    await _prefs.setStringList(
      StorageKeys.favorites,
      items.map((a) => jsonEncode(a.toJson())).toList(),
    );
  }

  Future<void> clear() async {
    await _prefs.remove(StorageKeys.favorites);
  }
}
