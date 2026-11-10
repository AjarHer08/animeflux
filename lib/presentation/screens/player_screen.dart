/// Player screen — video player dengan mirror, quality, speed, PiP, resume.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/constants.dart';
import '../../core/utils/logger.dart';
import '../../data/models/anime.dart';
import '../../data/models/episode.dart';
import '../../data/models/watch_history.dart';
import '../../data/repositories/anime_repository.dart';
import '../../data/scrapers/scraper_utils.dart';
import '../providers/favorites_providers.dart';
import '../widgets/adblock_webview.dart';
import '../widgets/episode_download_sheet.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final Anime anime;
  final Episode episode;
  final Duration? resumeFrom;
  const PlayerScreen({
    super.key,
    required this.anime,
    required this.episode,
    this.resumeFrom,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;

  bool _loading = true;
  bool _error = false;
  String _errorMessage = '';
  List<StreamMirror> _mirrors = [];
  int _selectedMirror = 0;
  VideoQuality _quality = VideoQuality.q720;
  double _speed = 1.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _showControls = true;
  Timer? _hideTimer;
  bool _landscape = false;
  int _lastSavedSecond = -100;
  bool _playing = false;

  /// Kalau tidak null, mirror dimainkan lewat WebView ber-adblock (fallback
  /// saat URL video langsung tidak bisa di-resolve dari halaman embed).
  String? _webUrl;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    WakelockPlus.enable();
    _attachListeners();
    _loadEpisode();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    WakelockPlus.disable();
    // Kembalikan orientasi — kalau tidak, app terkunci landscape setelah keluar.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _player.dispose();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future<void> _loadEpisode() async {
    _safeSetState(() {
      _loading = true;
      _error = false;
      _errorMessage = '';
    });
    try {
      final ep = await animeRepository.getEpisodeDetail(
        widget.anime.source,
        widget.episode,
      );
      _mirrors = ep.mirrors;
      if (_mirrors.isEmpty) {
        _safeSetState(() {
          _loading = false;
          _error = true;
          _errorMessage =
              'Tidak ada mirror streaming untuk episode ini dari ${widget.anime.source.label}. '
              'Gunakan tombol download, atau buka halaman episodenya di browser.';
        });
        return;
      }
      await _playMirror(0);
    } catch (e) {
      _safeSetState(() {
        _loading = false;
        _error = true;
        _errorMessage = 'Gagal memuat episode: $e';
      });
    }
  }

  Future<void> _playMirror(int index) async {
    if (index < 0 || index >= _mirrors.length) return;
    _safeSetState(() {
      _loading = true;
      _error = false;
      _webUrl = null;
      _selectedMirror = index;
    });
    await _player.stop();

    final mirror = _mirrors[index];
    final source = widget.anime.source;

    // 1) URL embed final (Otakudesu perlu AJAX untuk mirror tertentu).
    String? embed;
    try {
      embed = await animeRepository.resolveMirrorEmbed(source, mirror);
    } catch (e) {
      logger.w('resolveMirrorEmbed: $e');
    }
    if (!mounted) return;

    // 2) URL video langsung.
    String? direct = mirror.directUrl;
    if (direct == null || direct.isEmpty) {
      final dl = mirror.downloads
          .where((d) => d.quality == _quality && isDirectMediaUrl(d.url))
          .firstOrNull;
      if (dl != null) direct = dl.url;
    }
    if ((direct == null || direct.isEmpty) && embed != null && embed.isNotEmpty) {
      direct = isDirectMediaUrl(embed)
          ? embed
          : await animeRepository.resolveDirectUrl(source, embed);
    }
    if (!mounted) return;

    if (direct != null && direct.isNotEmpty) {
      final ok = await _openDirect(direct, embed);
      if (ok) return;
    }

    // 3) Fallback: putar embed asli di WebView ber-adblock. Mirror yang
    //    "aman" di situs aslinya tetap jalan walau URL videonya tersembunyi
    //    di balik JavaScript.
    if (embed != null && embed.isNotEmpty) {
      _safeSetState(() {
        _webUrl = embed;
        _loading = false;
      });
      return;
    }
    _safeSetState(() {
      _loading = false;
      _error = true;
      _errorMessage = 'Mirror "${mirror.label}" tidak bisa dibuka. Coba mirror lain.';
    });
  }

  Future<bool> _openDirect(String url, String? embed) async {
    try {
      final origin = Uri.tryParse(embed ?? url)?.origin ?? '';
      await _player.open(Media(
        url,
        httpHeaders: {
          'User-Agent': kDesktopUserAgents[0],
          if (origin.isNotEmpty) 'Referer': '$origin/',
        },
      ));
      await _player.setRate(_speed);
      Duration? resume = widget.resumeFrom;
      if (resume == null || resume.inSeconds <= 5) {
        final repo = await ref.read(historyRepositoryProvider.future);
        resume = repo.getResumePosition(widget.anime.id, widget.episode.id);
      }
      if (resume != null && resume.inSeconds > 5) {
        await _player.seek(resume);
      }
      _safeSetState(() => _loading = false);
      return true;
    } catch (e) {
      logger.w('Player.open gagal: $e');
      return false;
    }
  }

  /// Dipasang SEKALI di initState (sebelumnya dipasang ulang tiap ganti
  /// mirror → listener dobel + setState setelah dispose).
  void _attachListeners() {
    _subs.add(_player.stream.position.listen((p) {
      _safeSetState(() => _position = p);
      if (p.inSeconds - _lastSavedSecond >= 10) {
        _lastSavedSecond = p.inSeconds;
        _saveHistory();
      }
    }));
    _subs.add(_player.stream.duration.listen((d) {
      _safeSetState(() => _duration = d);
    }));
    _subs.add(_player.stream.playing.listen((v) {
      _safeSetState(() => _playing = v);
    }));
    _subs.add(_player.stream.completed.listen((done) {
      if (done) _saveHistory(forceCompleted: true);
    }));
    _subs.add(_player.stream.error.listen((e) {
      if (e.isEmpty || _webUrl != null) return;
      logger.e('Player error: $e');
      // Format tidak didukung / link kadaluarsa → coba lewat WebView.
      final mirror = (_selectedMirror < _mirrors.length) ? _mirrors[_selectedMirror] : null;
      final fallback = mirror?.embedUrl ?? '';
      if (fallback.startsWith('http')) {
        _safeSetState(() {
          _webUrl = fallback;
          _loading = false;
          _error = false;
        });
      } else {
        _safeSetState(() {
          _error = true;
          _errorMessage = 'Error player: $e';
        });
      }
    }));
  }

  Future<void> _saveHistory({bool forceCompleted = false}) async {
    if (_duration.inSeconds == 0 || !mounted) return;
    final repo = await ref.read(historyRepositoryProvider.future);
    await repo.record(WatchHistoryEntry(
      animeId: widget.anime.id,
      animeTitle: widget.anime.title,
      animeCover: widget.anime.cover,
      source: widget.anime.source,
      episodeId: widget.episode.id,
      episodeTitle: widget.episode.title,
      episodeUrl: widget.episode.url,
      position: forceCompleted ? _duration : _position,
      duration: _duration,
      watchedAt: DateTime.now(),
    ));
    ref.invalidate(historyListProvider);
  }

  void _showHideControls() {
    setState(() => _showControls = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  Future<void> _setSpeed(double s) async {
    setState(() => _speed = s);
    await _player.setRate(s);
  }

  Future<void> _setQuality(VideoQuality q) async {
    setState(() => _quality = q);
    await _playMirror(_selectedMirror);
  }

  Future<void> _togglePiP() async {
    // Picture-in-Picture via platform channel.
    // Untuk Android, panggil method `enterPictureInPictureMode` dari MainActivity.
    // Plugin `floating` adalah wrapper yang lebih kompleks. Untuk keep simple,
    // panggil via platform channel custom — diaktifkan jika MainActivity support.
    try {
      await const MethodChannel('animeflux/pip').invokeMethod('enterPiP');
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Picture-in-Picture belum didukung di perangkat ini. Aktifkan via MainActivity (Android 8+).')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PiP gagal: $e')),
        );
      }
    }
  }

  Future<void> _skipIntro() async {
    final cur = _player.state.position;
    await _player.seek(cur + const Duration(seconds: 85));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    final playerArea = Stack(
      children: [
        if (_webUrl != null)
          Positioned.fill(
            child: AdblockWebView(
              key: ValueKey(_webUrl),
              url: _webUrl!,
              lockNavigation: true,
              referer: '${Uri.parse(widget.episode.url).origin}/',
            ),
          )
        else
          Positioned.fill(
            child: GestureDetector(
              onTap: _showHideControls,
              child: Video(
                controller: _controller,
                fit: BoxFit.contain,
                fill: Colors.black,
              ),
            ),
          ),
        if (_loading)
          const Positioned.fill(child: Center(child: CircularProgressIndicator()))
        else if (_error)
          Positioned.fill(
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(24),
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error, color: scheme.error, size: 48),
                      const SizedBox(height: 12),
                      Text(_errorMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          if (_mirrors.length > 1)
                            FilledButton.icon(
                              onPressed: () => _playMirror((_selectedMirror + 1) % _mirrors.length),
                              icon: const Icon(Icons.skip_next),
                              label: const Text('Mirror lain'),
                            ),
                          FilledButton.tonalIcon(
                            onPressed: () =>
                                showEpisodeDownloadSheet(context, widget.anime, widget.episode),
                            icon: const Icon(Icons.download),
                            label: const Text('Download'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else if (_webUrl != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildWebBar(),
          )
        else if (_showControls)
          ..._buildControls(scheme, isLandscape),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: isLandscape
            ? playerArea
            : Column(
                children: [
                  AspectRatio(aspectRatio: 16 / 9, child: playerArea),
                  Expanded(child: _buildBottomInfo(scheme)),
                ],
              ),
      ),
    );
  }

  /// Bar tipis saat mode WebView: tombol kembali, download, ganti mirror.
  Widget _buildWebBar() {
    return Container(
      color: Colors.black54,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          if (_mirrors.length > 1)
            TextButton.icon(
              icon: const Icon(Icons.swap_horiz, color: Colors.white, size: 18),
              label: const Text('Mirror', style: TextStyle(color: Colors.white)),
              onPressed: _showMirrorSheet,
            ),
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            tooltip: 'Download',
            onPressed: () => showEpisodeDownloadSheet(context, widget.anime, widget.episode),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildControls(ColorScheme scheme, bool isLandscape) {
    return [
      // Top bar
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.6), Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () async {
                  await _saveHistory();
                  if (mounted) Navigator.pop(context);
                },
              ),
              Expanded(
                child: Text(
                  '${widget.anime.title} — ${widget.episode.title}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                tooltip: 'Download',
                onPressed: () => showEpisodeDownloadSheet(context, widget.anime, widget.episode),
              ),
              IconButton(
                icon: const Icon(Icons.picture_in_picture, color: Colors.white),
                tooltip: 'Picture-in-Picture',
                onPressed: _togglePiP,
              ),
              IconButton(
                icon: Icon(isLandscape ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                onPressed: () {
                  setState(() => _landscape = !_landscape);
                  if (_landscape) {
                    SystemChrome.setPreferredOrientations([
                      DeviceOrientation.landscapeLeft,
                    ]);
                  } else {
                    SystemChrome.setPreferredOrientations([
                      DeviceOrientation.portraitUp,
                    ]);
                  }
                },
              ),
            ],
          ),
        ),
      ),
      // Center controls
      Positioned.fill(
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white, size: 32),
                onPressed: () async {
                  final cur = _player.state.position;
                  await _player.seek(cur - const Duration(seconds: 10));
                },
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 56,
                ),
                onPressed: () => _player.playOrPause(),
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white, size: 32),
                onPressed: () async {
                  final cur = _player.state.position;
                  await _player.seek(cur + const Duration(seconds: 10));
                },
              ),
            ],
          ),
        ),
      ),
      // Bottom controls
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black.withOpacity(0.6), Colors.transparent],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress bar
              Row(
                children: [
                  Text(
                    _formatDuration(_position),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Expanded(
                    child: Slider(
                      value: _position.inSeconds
                          .toDouble()
                          .clamp(0.0, _duration.inSeconds.toDouble().clamp(1.0, double.maxFinite))
                          .toDouble(),
                      max: _duration.inSeconds.toDouble().clamp(1.0, double.maxFinite).toDouble(),
                      onChanged: (v) async {
                        await _player.seek(Duration(seconds: v.toInt()));
                      },
                    ),
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mirror selector
                  if (_mirrors.length > 1)
                    TextButton.icon(
                      icon: const Icon(Icons.swap_horiz, color: Colors.white, size: 18),
                      label: Text(
                        _mirrors[_selectedMirror].label,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      onPressed: () => _showMirrorSheet(),
                    ),
                  // Quality selector
                  if (_mirrors.isNotEmpty && _mirrors[_selectedMirror].downloads.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.high_quality, color: Colors.white, size: 18),
                      label: Text(
                        _quality.label,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      onPressed: () => _showQualitySheet(),
                    ),
                  // Speed
                  TextButton.icon(
                    icon: const Icon(Icons.speed, color: Colors.white, size: 18),
                    label: Text(
                      '${_speed}x',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    onPressed: () => _showSpeedSheet(),
                  ),
                  // Skip intro
                  TextButton.icon(
                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 18),
                    label: const Text(
                      'Skip 85s',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    onPressed: _skipIntro,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildBottomInfo(ColorScheme scheme) {
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.anime.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          Text(
            widget.episode.title,
            style: TextStyle(color: scheme.outline),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_mirrors.length > 1)
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    children: List.generate(_mirrors.length, (i) {
                      final m = _mirrors[i];
                      return ChoiceChip(
                        label: Text(m.label, style: const TextStyle(fontSize: 12)),
                        selected: i == _selectedMirror,
                        onSelected: (_) => _playMirror(i),
                      );
                    }),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    'Sumber: ${widget.anime.source.label} • ${_mirrors.isNotEmpty ? _mirrors.first.label : "—"}',
                    style: TextStyle(color: scheme.outline, fontSize: 12),
                  ),
                ),
            ],
          ),
          const Spacer(),
          if (widget.anime.synopsis != null) ...[
            Text('Sinopsis',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    )),
            const SizedBox(height: 4),
            Text(
              widget.anime.synopsis!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.outline, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  void _showMirrorSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Pilih Mirror',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            ListView.builder(
              shrinkWrap: true,
              itemCount: _mirrors.length,
              itemBuilder: (context, i) {
                final m = _mirrors[i];
                return ListTile(
                  leading: Icon(
                    i == _selectedMirror ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: i == _selectedMirror ? Theme.of(context).colorScheme.primary : null,
                  ),
                  title: Text(m.label),
                  subtitle: Text(m.server),
                  onTap: () {
                    Navigator.pop(context);
                    _playMirror(i);
                  },
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showQualitySheet() {
    if (_mirrors.isEmpty) return;
    final downloads = _mirrors[_selectedMirror].downloads;
    final qualities = <VideoQuality>{};
    for (final d in downloads) {
      if (d.quality != null) qualities.add(d.quality!);
    }
    if (qualities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada opsi quality untuk mirror ini.')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Pilih Resolusi',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final q in VideoQuality.values)
              if (qualities.contains(q))
                ListTile(
                  leading: Icon(
                    q == _quality ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: q == _quality ? Theme.of(context).colorScheme.primary : null,
                  ),
                  title: Text(q.label),
                  onTap: () {
                    Navigator.pop(context);
                    _setQuality(q);
                  },
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSpeedSheet() {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Kecepatan Putar',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            Wrap(
              spacing: 8,
              children: speeds.map((s) {
                return ChoiceChip(
                  label: Text('${s}x'),
                  selected: _speed == s,
                  onSelected: (_) {
                    Navigator.pop(context);
                    _setSpeed(s);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }
}

// Suppress unused warning
// ignore: unused_element
final _unused = SourceId.otakudesu;
