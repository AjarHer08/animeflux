/// Pengaturan pemblokir iklan (gaya AdGuard / uBlock Origin).
library;

import 'package:flutter/material.dart';
import '../widgets/glass.dart';

import '../../core/adblock/adblock_engine.dart';

class AdblockScreen extends StatelessWidget {
  const AdblockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = AdblockEngine.instance;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: GlassAppBar(title: const Text('Pemblokir Iklan')),
      body: ListenableBuilder(
        listenable: engine,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: scheme.surfaceContainerHighest,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Engine bawaan aplikasi, bekerja di player embed dan browser download. '
                    'Membaca filter list berformat AdGuard/uBlock/EasyList. '
                    'Ini bukan ekstensi browser Chrome/Firefox — ekstensi itu tidak bisa '
                    'dimuat di Android WebView — tapi fungsinya setara untuk halaman yang dibuka dari app.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Aktifkan pemblokir iklan'),
                subtitle: Text(engine.busy
                    ? 'Memproses filter...'
                    : '${engine.totalRules} aturan aktif'),
                value: engine.enabled,
                onChanged: engine.setEnabled,
              ),
              SwitchListTile(
                title: const Text('Blokir popup & redirect'),
                subtitle: Text('Dibatalkan sesi ini: ${engine.blockedCount}'),
                value: engine.blockPopups,
                onChanged: engine.enabled ? engine.setBlockPopups : null,
              ),
              SwitchListTile(
                title: const Text('Sembunyikan elemen iklan'),
                subtitle: const Text('Banner & kotak iklan yang lolos dari blokir jaringan'),
                value: engine.cosmetic,
                onChanged: engine.enabled ? engine.setCosmetic : null,
              ),
              if (engine.message != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(engine.message!, style: TextStyle(color: scheme.error)),
                ),
              const Divider(height: 32),
              Row(
                children: [
                  Expanded(
                    child: Text('Filter list',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  TextButton.icon(
                    onPressed: engine.updateAllEnabled,
                    icon: const Icon(Icons.sync),
                    label: const Text('Perbarui'),
                  ),
                ],
              ),
              for (final l in engine.lists)
                SwitchListTile(
                  isThreeLine: true,
                  title: Text(l.name),
                  subtitle: Text(
                    [
                      l.description,
                      if (l.enabled) '${l.ruleCount} aturan',
                      if (l.updatedAt != null) 'diperbarui ${_fmt(l.updatedAt!)}',
                      if (l.downloading) 'mengunduh...',
                      if (l.error != null) 'Error: ${l.error}',
                    ].where((e) => e.isNotEmpty).join(' • '),
                    style: TextStyle(color: l.error != null ? scheme.error : null, fontSize: 12),
                  ),
                  secondary: l.custom
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => engine.removeList(l.id),
                        )
                      : (l.downloading
                          ? const SizedBox(
                              width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : null),
                  value: l.enabled,
                  onChanged: l.downloading ? null : (v) => engine.setListEnabled(l.id, v),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add_link),
                    label: const Text('Tambah list (URL)'),
                    onPressed: () => _addList(context),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Aturan kustom'),
                    onPressed: () => _editRules(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Catatan: list besar (EasyList, AdGuard) diunduh dari server resmi masing-masing dan '
                'hanya sebagian sintaks yang didukung (blokir domain, pola path, dan sembunyikan elemen). '
                'Aturan prosedural/scriptlet dilewati.',
                style: TextStyle(color: scheme.outline, fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _addList(BuildContext context) async {
    final name = TextEditingController();
    final url = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tambah filter list'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama (opsional)')),
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'URL (https://...)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tambah')),
        ],
      ),
    );
    final u = url.text.trim();
    if (ok == true && u.startsWith('http')) {
      await AdblockEngine.instance.addCustomList(name.text.trim(), u);
    }
  }

  Future<void> _editRules(BuildContext context) async {
    final c = TextEditingController(text: AdblockEngine.instance.customRules);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Aturan kustom'),
        content: TextField(
          controller: c,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: '||iklan.example.com^\nsitus.com##.banner',
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (ok == true) await AdblockEngine.instance.setCustomRules(c.text);
  }
}
