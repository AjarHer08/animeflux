/// Theme system — Material 3 dark default + presets + custom wallpaper.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';

/// Preset tema yang tersedia untuk dipilih user.
class ThemePreset {
  final String id;
  final String name;
  final Color seed;
  final Brightness brightness;
  final String? description;

  const ThemePreset({
    required this.id,
    required this.name,
    required this.seed,
    required this.brightness,
    this.description,
  });

  static const List<ThemePreset> all = [
    ThemePreset(
      id: 'indigo_dark',
      name: 'Indigo Dark',
      seed: Color(0xFF6750A4),
      brightness: Brightness.dark,
      description: 'Default ala Otakudesu — ungu klasik',
    ),
    ThemePreset(
      id: 'ocean_dark',
      name: 'Ocean Dark',
      seed: Color(0xFF0061A4),
      brightness: Brightness.dark,
      description: 'Biru navy ala lendrive',
    ),
    ThemePreset(
      id: 'neon_dark',
      name: 'Neon Dark',
      seed: Color(0xFFE91E63),
      brightness: Brightness.dark,
      description: 'Hitam pekat dengan accent neon pink ala Hidoristream',
    ),
    ThemePreset(
      id: 'amber_dark',
      name: 'Amber Dark',
      seed: Color(0xFFFFB300),
      brightness: Brightness.dark,
      description: 'Hitam dengan accent amber keemasan',
    ),
    ThemePreset(
      id: 'emerald_dark',
      name: 'Emerald Dark',
      seed: Color(0xFF006B5B),
      brightness: Brightness.dark,
      description: 'Hijau gelap — fresh dan calming',
    ),
    ThemePreset(
      id: 'rose_dark',
      name: 'Rose Dark',
      seed: Color(0xFFB3261E),
      brightness: Brightness.dark,
      description: 'Merah rose — elegan dan dramatik',
    ),
    ThemePreset(
      id: 'mono_dark',
      name: 'Mono Dark',
      seed: Color(0xFF424242),
      brightness: Brightness.dark,
      description: 'Monokrom — minimalis tanpa warna kuat',
    ),
    ThemePreset(
      id: 'light_amber',
      name: 'Light Amber',
      seed: Color(0xFF8E4A2C),
      brightness: Brightness.light,
      description: 'Mode terang dengan accent amber',
    ),
  ];

  static ThemePreset byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => all.first);
}

/// Konfigurasi tema yang disimpan.
class ThemeConfig {
  final String presetId;
  final bool useCustomSeed;
  final Color? customSeed;
  final bool useWallpaper;
  final String? wallpaperPath;
  final double wallpaperOpacity;
  final Brightness? overrideBrightness;

  const ThemeConfig({
    this.presetId = 'indigo_dark',
    this.useCustomSeed = false,
    this.customSeed,
    this.useWallpaper = false,
    this.wallpaperPath,
    this.wallpaperOpacity = 0.4,
    this.overrideBrightness,
  });

  ThemeConfig copyWith({
    String? presetId,
    bool? useCustomSeed,
    Color? customSeed,
    bool? useWallpaper,
    String? wallpaperPath,
    double? wallpaperOpacity,
    Brightness? overrideBrightness,
  }) {
    return ThemeConfig(
      presetId: presetId ?? this.presetId,
      useCustomSeed: useCustomSeed ?? this.useCustomSeed,
      customSeed: customSeed ?? this.customSeed,
      useWallpaper: useWallpaper ?? this.useWallpaper,
      wallpaperPath: wallpaperPath ?? this.wallpaperPath,
      wallpaperOpacity: wallpaperOpacity ?? this.wallpaperOpacity,
      overrideBrightness: overrideBrightness ?? this.overrideBrightness,
    );
  }

  ThemePreset get preset => ThemePreset.byId(presetId);
  Color get effectiveSeed =>
      useCustomSeed && customSeed != null ? customSeed! : preset.seed;
  Brightness get effectiveBrightness =>
      overrideBrightness ?? preset.brightness;

  Map<String, dynamic> toJson() => {
        'presetId': presetId,
        'useCustomSeed': useCustomSeed,
        'customSeed': customSeed?.value,
        'useWallpaper': useWallpaper,
        'wallpaperPath': wallpaperPath,
        'wallpaperOpacity': wallpaperOpacity,
        'overrideBrightness': overrideBrightness?.name,
      };

  factory ThemeConfig.fromJson(Map<String, dynamic> json) {
    return ThemeConfig(
      presetId: json['presetId'] as String? ?? 'indigo_dark',
      useCustomSeed: json['useCustomSeed'] as bool? ?? false,
      customSeed:
          json['customSeed'] != null ? Color(json['customSeed'] as int) : null,
      useWallpaper: json['useWallpaper'] as bool? ?? false,
      wallpaperPath: json['wallpaperPath'] as String?,
      wallpaperOpacity: (json['wallpaperOpacity'] as num?)?.toDouble() ?? 0.4,
      overrideBrightness: json['overrideBrightness'] == null
          ? null
          : Brightness.values.byName(json['overrideBrightness'] as String),
    );
  }
}

/// SharedPreferences instance holder — di-init di main() sebelum runApp.
late SharedPreferences _sharedPrefs;
SharedPreferences get sharedPreferencesInstance => _sharedPrefs;
void initSharedPreferences(SharedPreferences prefs) {
  _sharedPrefs = prefs;
}

/// Notifier untuk tema.
class ThemeNotifier extends StateNotifier<ThemeConfig> {
  ThemeNotifier(this._prefs) : super(const ThemeConfig()) {
    _load();
  }

  final SharedPreferences _prefs;

  void _load() {
    final raw = _prefs.getString('${StorageKeys.settings}::theme');
    if (raw != null) {
      try {
        state = ThemeConfig.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      } catch (_) {
        // ignore
      }
    }
  }

  Future<void> setPreset(String presetId) async {
    state = state.copyWith(presetId: presetId, useCustomSeed: false);
    await _save();
  }

  Future<void> setCustomSeed(Color color) async {
    state = state.copyWith(useCustomSeed: true, customSeed: color);
    await _save();
  }

  Future<void> setWallpaper(String? path, {double? opacity}) async {
    state = state.copyWith(
      useWallpaper: path != null,
      wallpaperPath: path,
      wallpaperOpacity: opacity ?? state.wallpaperOpacity,
    );
    await _save();
  }

  Future<void> setWallpaperOpacity(double opacity) async {
    state = state.copyWith(wallpaperOpacity: opacity);
    await _save();
  }

  Future<void> setBrightness(Brightness? brightness) async {
    state = state.copyWith(overrideBrightness: brightness);
    await _save();
  }

  Future<void> reset() async {
    state = const ThemeConfig();
    await _save();
  }

  Future<void> _save() async {
    await _prefs.setString(
      '${StorageKeys.settings}::theme',
      jsonEncode(state.toJson()),
    );
  }
}

/// Provider untuk ThemeConfig.
final themeProvider =
    StateNotifierProvider<ThemeNotifier, ThemeConfig>((ref) {
  return ThemeNotifier(sharedPreferencesInstance);
});

/// Build ThemeData dari ThemeConfig.
ThemeData buildThemeData(ThemeConfig config) {
  final scheme = ColorScheme.fromSeed(
    seedColor: config.effectiveSeed,
    brightness: config.effectiveBrightness,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
    ),
    cardTheme: CardTheme(
      elevation: 0,
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
    ),
  );
}

/// Widget untuk background yang menampilkan wallpaper (jika aktif).
class ThemedBackground extends ConsumerWidget {
  final Widget child;
  const ThemedBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    if (!theme.useWallpaper ||
        theme.wallpaperPath == null ||
        theme.wallpaperPath!.isEmpty) {
      return child;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          theme.wallpaperPath!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox(),
        ),
        ColoredBox(
          color: Theme.of(context).colorScheme.surface
              .withOpacity(1 - theme.wallpaperOpacity),
        ),
        child,
      ],
    );
  }
}
