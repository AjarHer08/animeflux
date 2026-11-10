/// Akun lokal AnimeFlux (disimpan di perangkat).
///
/// Belum ada server akun, jadi login ini hanya profil lokal. Status VIP
/// disiapkan sebagai field supaya bisa dihubungkan ke backend nanti lewat
/// [setVip]; tanpa backend VIP tidak bisa diaktifkan dari UI.
library;

import 'package:flutter/foundation.dart';

import '../theme/app_theme.dart' show sharedPreferencesInstance;

class AccountService extends ChangeNotifier {
  AccountService._();
  static final AccountService instance = AccountService._();

  static const _kName = 'account_name_v1';
  static const _kEmail = 'account_email_v1';
  static const _kVip = 'account_vip_v1';

  String? get name => sharedPreferencesInstance.getString(_kName);
  String? get email => sharedPreferencesInstance.getString(_kEmail);
  bool get isLoggedIn => (name ?? '').isNotEmpty;
  bool get isVip => isLoggedIn && (sharedPreferencesInstance.getBool(_kVip) ?? false);

  Future<void> login({required String name, String? email}) async {
    await sharedPreferencesInstance.setString(_kName, name.trim());
    await sharedPreferencesInstance.setString(_kEmail, (email ?? '').trim());
    notifyListeners();
  }

  Future<void> logout() async {
    await sharedPreferencesInstance.remove(_kName);
    await sharedPreferencesInstance.remove(_kEmail);
    await sharedPreferencesInstance.remove(_kVip);
    notifyListeners();
  }

  /// Hook untuk backend (belum dipakai UI).
  Future<void> setVip(bool value) async {
    await sharedPreferencesInstance.setBool(_kVip, value);
    notifyListeners();
  }
}
