/// Settings screen — pilih tema, wallpaper, brightness, tentang.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/adblock/adblock_engine.dart';
import '../../core/constants.dart';
import '../../core/theme/app_theme.dart';
import '../providers/favorites_providers.dart';
import '../../data/models/comic.dart';
import '../widgets/glass.dart';
import '../widgets/update_dialog.dart';
import 'account_screen.dart';
import 'adblock_screen.dart';
import 'downloads_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final theme = ref.watch(themeProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pengaturan',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),

            // === Tema ===
            _SectionCard(
              title: 'Tema',
              icon: Icons.palette,
              children: [
                // Preset
                const SizedBox(height: 8),
                Text('Pilih tema bawaan',
                    style: TextStyle(color: scheme.outline, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ThemePreset.all.map((p) {
                    final active = theme.presetId == p.id && !theme.useCustomSeed;
                    return ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: p.seed,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(p.name),
                        ],
                      ),
                      selected: active,
                      onSelected: (_) =>
                          ref.read(themeProvider.notifier).setPreset(p.id),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Efek liquid glass'),
                  subtitle: const Text('Latar kaca buram di bar navigasi & app bar'),
                  value: ref.watch(glassEnabledProvider),
                  onChanged: (v) => ref.read(glassEnabledProvider.notifier).set(v),
                ),
                const SizedBox(height: 8),

                // Brightness
                Text('Mode tampilan',
                    style: TextStyle(color: scheme.outline, fontSize: 13)),
                const SizedBox(height: 8),
                SegmentedButton<Brightness?>(
                  segments: const [
                    ButtonSegment(value: null, label: Text('Otomatis')),
                    ButtonSegment(value: Brightness.dark, label: Text('Dark')),
                    ButtonSegment(value: Brightness.light, label: Text('Light')),
                  ],
                  selected: {theme.overrideBrightness},
                  onSelectionChanged: (s) =>
                      ref.read(themeProvider.notifier).setBrightness(s.first),
                ),
                const SizedBox(height: 16),

                // Custom seed color
                SwitchListTile(
                  title: const Text('Pakai warna custom'),
                  subtitle: const Text('Override preset dengan warna pilihanmu'),
                  value: theme.useCustomSeed,
                  onChanged: (v) async {
                    if (!v) {
                      await ref.read(themeProvider.notifier).setPreset(theme.presetId);
                      return;
                    }
                    final color = await _pickColor(context);
                    if (color != null) {
                      ref.read(themeProvider.notifier).setCustomSeed(color);
                    }
                  },
                ),
                if (theme.useCustomSeed && theme.customSeed != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ColorPickerRow(
                      color: theme.customSeed!,
                      onColorChanged: (c) =>
                          ref.read(themeProvider.notifier).setCustomSeed(c),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // === Wallpaper ===
            _SectionCard(
              title: 'Wallpaper',
              icon: Icons.wallpaper,
              children: [
                SwitchListTile(
                  title: const Text('Pakai wallpaper dari galeri'),
                  subtitle: const Text(
                      'Pilih foto dari galeri sebagai background aplikasi'),
                  value: theme.useWallpaper,
                  onChanged: (v) async {
                    if (!v) {
                      await ref.read(themeProvider.notifier).setWallpaper(null);
                      return;
                    }
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 80,
                    );
                    if (picked != null) {
                      // Path dari picker adalah cache sementara yang bisa
                      // terhapus -> salin ke penyimpanan app supaya awet.
                      final saved = await _persistWallpaper(
                          picked.path, theme.wallpaperPath);
                      await ref.read(themeProvider.notifier).setWallpaper(saved);
                    }
                  },
                ),
                if (theme.useWallpaper && theme.wallpaperPath != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(theme.wallpaperPath!),
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 120,
                          color: scheme.surfaceContainerHighest,
                          child: const Center(child: Icon(Icons.broken_image)),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        const Text('Opasitas'),
                        Expanded(
                          child: Slider(
                            min: 0,
                            max: 1,
                            value: theme.wallpaperOpacity,
                            onChanged: (v) =>
                                ref.read(themeProvider.notifier).setWallpaperOpacity(v),
                          ),
                        ),
                        Text('${(theme.wallpaperOpacity * 100).round()}%'),
                      ],
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 16),

            // === Akun ===
            _SectionCard(
              title: 'Akun',
              icon: Icons.account_circle,
              children: [
                ListTile(
                  leading: const Icon(Icons.login),
                  title: const Text('Akun & Login'),
                  subtitle: const Text('Profil & status VIP'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AccountScreen()),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // === Ekstensi / pemblokir iklan ===
            _SectionCard(
              title: 'Ekstensi',
              icon: Icons.extension,
              children: [
                ListenableBuilder(
                  listenable: AdblockEngine.instance,
                  builder: (context, _) => ListTile(
                    leading: const Icon(Icons.shield),
                    title: const Text('Pemblokir Iklan (gaya AdGuard / uBlock)'),
                    subtitle: Text(AdblockEngine.instance.enabled
                        ? 'Aktif • ${AdblockEngine.instance.totalRules} aturan'
                        : 'Nonaktif'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdblockScreen()),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.dns),
                  title: const Text('Domain sumber komik'),
                  subtitle: const Text('Ubah jika situs pindah domain (mis. v7 → v8)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editDomains(context),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // === Library ===
            _SectionCard(
              title: 'Library',
              icon: Icons.collections_bookmark,
              children: [
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Download Manager'),
                  subtitle: const Text('Lihat & kelola download berjalan'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DownloadsScreen()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.bookmark),
                  title: const Text('Favorit'),
                  subtitle: const Text('Anime yang kamu bookmark'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Switch ke tab favorit
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // === Reset ===
            _SectionCard(
              title: 'Data',
              icon: Icons.storage,
              children: [
                ListTile(
                  leading: Icon(Icons.delete_forever, color: scheme.error),
                  title: Text('Hapus semua favorit',
                      style: TextStyle(color: scheme.error)),
                  onTap: () async {
                    final ok = await _confirm(context, 'Hapus semua favorit?');
                    if (ok != true) return;
                    final repo = await ref.read(favoritesRepositoryProvider.future);
                    await repo.clear();
                    ref.invalidate(favoritesListProvider);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_forever, color: scheme.error),
                  title: Text('Hapus riwayat tonton',
                      style: TextStyle(color: scheme.error)),
                  onTap: () async {
                    final ok = await _confirm(context, 'Hapus semua riwayat?');
                    if (ok != true) return;
                    final repo = await ref.read(historyRepositoryProvider.future);
                    await repo.clear();
                    ref.invalidate(historyListProvider);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.restart_alt, color: scheme.error),
                  title: Text('Reset tema ke default',
                      style: TextStyle(color: scheme.error)),
                  onTap: () async {
                    final ok = await _confirm(context, 'Reset tema?');
                    if (ok != true) return;
                    await ref.read(themeProvider.notifier).reset();
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // === About ===
            _SectionCard(
              title: 'Tentang',
              icon: Icons.info_outline,
              children: [
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    return ListTile(
                      leading: const Icon(Icons.android),
                      title: const Text('AnimeFlux'),
                      subtitle: Text(
                        snapshot.hasData
                            ? 'v${snapshot.data!.version}+${snapshot.data!.buildNumber}'
                            : 'v$kAppVersion',
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.system_update),
                  title: const Text('Cek pembaruan'),
                  subtitle: const Text('Periksa versi terbaru di GitHub'),
                  onTap: () => checkForUpdateManually(context),
                ),
                const ListTile(
                  leading: Icon(Icons.code),
                  title: Text('Sumber'),
                  subtitle: Text('Anime: Otakudesu, Hidoristream, Lendrive • Komik: Komiku, Komikstation, Kiryuu'),
                ),
                const ListTile(
                  leading: Icon(Icons.shield_outlined),
                  title: Text('Catatan Hukum'),
                  subtitle: Text(
                      'Aplikasi ini hanya sebagai jembatan (scraping) ke sumber publik. Konten tetap milik pemilik masing-masing.'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Salin wallpaper pilihan ke folder dokumen app; hapus wallpaper lama.
  Future<String> _persistWallpaper(String pickedPath, String? oldPath) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dot = pickedPath.lastIndexOf('.');
      final ext = (dot > pickedPath.lastIndexOf('/') && dot != -1)
          ? pickedPath.substring(dot)
          : '.jpg';
      final dest = '${dir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}$ext';
      await File(pickedPath).copy(dest);
      if (oldPath != null && oldPath.startsWith(dir.path)) {
        try {
          await File(oldPath).delete();
        } catch (_) {}
      }
      return dest;
    } catch (_) {
      return pickedPath;
    }
  }

  Future<void> _editDomains(BuildContext context) async {
    final ctrls = {
      for (final s in ComicSourceId.values) s: TextEditingController(text: s.baseUrl),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Domain sumber komik'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in ComicSourceId.values)
                TextField(
                  controller: ctrls[s],
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(labelText: s.label, hintText: s.defaultBaseUrl),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true) return;
    for (final s in ComicSourceId.values) {
      final v = ctrls[s]!.text.trim();
      await s.setBaseUrl(v == s.defaultBaseUrl ? null : v);
    }
  }

  Future<bool?> _confirm(BuildContext context, String title) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ya')),
        ],
      ),
    );
  }

  Future<Color?> _pickColor(BuildContext context) async {
    final colors = [
      Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
      Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
      Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
      Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
      Colors.brown, Colors.grey,
    ];
    Color picked = Colors.indigo;
    return showDialog<Color>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pilih warna'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: colors.map((c) {
            return InkWell(
              onTap: () => Navigator.pop(context, c),
              child: CircleAvatar(
                backgroundColor: c,
                radius: 18,
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Batal')),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class ColorPickerRow extends StatelessWidget {
  final Color color;
  final ValueChanged<Color> onColorChanged;
  const ColorPickerRow({super.key, required this.color, required this.onColorChanged});

  @override
  Widget build(BuildContext context) {
    final presets = [
      Colors.red, Colors.pink, Colors.purple, Colors.indigo,
      Colors.blue, Colors.teal, Colors.green, Colors.amber,
    ];
    return Wrap(
      spacing: 8,
      children: presets.map((c) {
        return InkWell(
          onTap: () => onColorChanged(c),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: color == c ? Colors.white : Colors.transparent,
                width: 2,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
