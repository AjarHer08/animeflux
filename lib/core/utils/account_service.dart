/// Akun lokal AnimeFlux (disimpan di perangkat).
///
/// Belum ada server akun, jadi login ini hanya profil lokal. Status VIP
/// disiapkan sebagai field supaya bisa dihubungkan ke backend nanti lewat
/// [setVip]; tanpa backend VIP tidak bisa diaktifkan dari UI.
library;

import 'package:flutter/foundation.dart';

import '../constants.dart' show kAdminName, kAdminCode;
import '../theme/app_theme.dart' show sharedPreferencesInstance;

class AccountService extends ChangeNotifier {
  AccountService._();
  static final AccountService instance = AccountService._();

  static const _kName = 'account_name_v1';
  static const _kEmail = 'account_email_v1';
  static const _kVip = 'account_vip_v1';
  static const _kAdmin = 'account_admin_v1';

  String? get name => sharedPreferencesInstance.getString(_kName);
  String? get email => sharedPreferencesInstance.getString(_kEmail);
  bool get isLoggedIn => (name ?? '').isNotEmpty;
  bool get isAdmin => isLoggedIn && (sharedPreferencesInstance.getBool(_kAdmin) ?? false);
  // Admin otomatis berstatus VIP.
  bool get isVip => isAdmin || (isLoggedIn && (sharedPreferencesInstance.getBool(_kVip) ?? false));

  /// Nama yang dipakai akun admin (tanpa membedakan huruf besar/kecil).
  static bool isAdminName(String name) => name.trim().toLowerCase() == kAdminName.toLowerCase();

  /// Login akun admin lokal. Mengembalikan false kalau kode salah.
  /// Catatan: pengecekan ini hanya di dalam aplikasi (tanpa server), jadi
  /// berfungsi sebagai pembeda profil, bukan pengamanan data.
  Future<bool> loginAdmin({required String code, String? email}) async {
    if (code.trim() != kAdminCode) return false;
    await sharedPreferencesInstance.setString(_kName, kAdminName);
    await sharedPreferencesInstance.setString(_kEmail, (email ?? '').trim());
    await sharedPreferencesInstance.setBool(_kAdmin, true);
    notifyListeners();
    return true;
  }

  Future<void> login({required String name, String? email}) async {
    await sharedPreferencesInstance.remove(_kAdmin);
    await sharedPreferencesInstance.setString(_kName, name.trim());
    await sharedPreferencesInstance.setString(_kEmail, (email ?? '').trim());
    notifyListeners();
  }

  Future<void> logout() async {
    await sharedPreferencesInstance.remove(_kName);
    await sharedPreferencesInstance.remove(_kEmail);
    await sharedPreferencesInstance.remove(_kVip);
    await sharedPreferencesInstance.remove(_kAdmin);
    notifyListeners();
  }

  /// Hook untuk backend (belum dipakai UI).
  Future<void> setVip(bool value) async {
    await sharedPreferencesInstance.setBool(_kVip, value);
    notifyListeners();
  }
}
