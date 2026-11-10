/// Bottom sheet daftar link download sebuah episode.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/anime.dart';
import '../../data/models/episode.dart';
import '../../data/repositories/anime_repository.dart';
import '../../data/scrapers/scraper_utils.dart';
import '../screens/browser_screen.dart';

Future<void> showEpisodeDownloadSheet(
  BuildContext context,
  Anime anime,
  Episode episode,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (ctx, scroll) =>
          _DownloadSheet(anime: anime, episode: episode, controller: scroll),
    ),
  );
}

class _DownloadSheet extends ConsumerStatefulWidget {
  final Anime anime;
  final Episode episode;
  final ScrollController controller;
  const _DownloadSheet({required this.anime, required this.episode, required this.controller});

  @override
  ConsumerState<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends ConsumerState<_DownloadSheet> {
  late Future<List<DownloadOption>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<DownloadOption>> _load() async {
    final ep = await animeRepository.getEpisodeDetail(widget.anime.source, widget.episode);
    final all = <DownloadOption>[...ep.downloads];
    for (final m in ep.mirrors) {
      for (final d in m.downloads) {
        if (!all.any((x) => x.url == d.url)) all.add(d);
      }
    }
    all.sort((a, b) => (b.quality?.height ?? 0).compareTo(a.quality?.height ?? 0));
    return all;
  }

  Future<void> _download(DownloadOption d) async {
    final nav = Navigator.of(context);
    if (isDirectMediaUrl(d.url)) {
      // Unduh langsung (HttpURLConnection) sering ditolak server file (butuh
      // cookie/UA browser). Jadi disiapkan lewat WebView dulu, lalu diunduh
      // dengan cookie + User-Agent yang sama.
      nav.pop();
      nav.push(MaterialPageRoute(
        builder: (_) => BrowserScreen(
          url: d.url,
          title: d.host ?? 'Download',
          autoDownloadUrl: d.url,
          referer: widget.episode.url,
          animeId: widget.anime.id,
          animeTitle: widget.anime.title,
          episodeTitle: widget.episode.title,
          cover: widget.anime.cover,
        ),
      ));
    } else {
      // Halaman file-host (acefile, pixeldrain, ...) — buka di browser
      // ber-adblock; download otomatis ditangkap begitu file dipilih.
      nav.pop();
      nav.push(MaterialPageRoute(
        builder: (_) => BrowserScreen(
          url: d.url,
          title: d.host ?? 'Download',
          animeId: widget.anime.id,
          animeTitle: widget.anime.title,
          episodeTitle: widget.episode.title,
          cover: widget.anime.cover,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<DownloadOption>>(
      future: _future,
      builder: (context, snap) {
        final children = <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Download — ${widget.episode.title}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ];
        if (snap.connectionState != ConnectionState.done) {
          children.add(const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ));
        } else if (snap.hasError) {
          children.addAll([
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Gagal memuat link: ${snap.error}', style: TextStyle(color: scheme.error)),
            ),
            Center(
              child: FilledButton.tonal(
                onPressed: () => setState(() => _future = _load()),
                child: const Text('Coba lagi'),
              ),
            ),
          ]);
        } else {
          final list = snap.data ?? const <DownloadOption>[];
          if (list.isEmpty) {
            children.add(Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Tidak ada link download yang terbaca dari halaman episode ini. '
                'Buka halaman episodenya langsung di browser ber-adblock di bawah.',
                style: TextStyle(color: scheme.outline),
              ),
            ));
          }
          for (final d in list) {
            children.add(ListTile(
              leading: Icon(isDirectMediaUrl(d.url) ? Icons.download : Icons.open_in_new),
              title: Text(d.label, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(d.host ?? Uri.tryParse(d.url)?.host ?? ''),
              onTap: () => _download(d),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'copy') {
                    await Clipboard.setData(ClipboardData(text: d.url));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Link disalin')));
                    }
                  } else if (v == 'ext') {
                    await launchUrl(Uri.parse(d.url), mode: LaunchMode.externalApplication);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'copy', child: Text('Salin link')),
                  PopupMenuItem(value: 'ext', child: Text('Buka di browser eksternal')),
                ],
              ),
            ));
          }
        }
        children.addAll([
          const Divider(),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('Buka halaman episode (browser ber-adblock)'),
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop();
              nav.push(MaterialPageRoute(
                builder: (_) => BrowserScreen(
                  url: widget.episode.url,
                  title: widget.episode.title,
                  animeId: widget.anime.id,
                  animeTitle: widget.anime.title,
                  episodeTitle: widget.episode.title,
                  cover: widget.anime.cover,
                ),
              ));
            },
          ),
        ]);
        return ListView(controller: widget.controller, children: children);
      },
    );
  }
}
