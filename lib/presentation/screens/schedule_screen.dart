/// Schedule screen — jadwal rilisan per hari dari sumber terpilih.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/models/anime.dart';
import '../../data/models/schedule.dart';
import '../../data/repositories/anime_repository.dart';
import '../widgets/source_selector.dart';
import 'detail_screen.dart';

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key, required this.source});
  final SourceId source;

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  late SourceId _source;
  late Future<List<DaySchedule>> _future;

  @override
  void initState() {
    super.initState();
    _source = widget.source;
    _future = animeRepository.getSchedule(_source);
  }

  void _refresh() {
    setState(() {
      _future = animeRepository.getSchedule(_source);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jadwal Rilis'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SourceSelector(
                value: _source,
                onChanged: (s) {
                  setState(() => _source = s);
                  _refresh();
                },
              ),
            ),
            Expanded(
              child: FutureBuilder<List<DaySchedule>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Gagal memuat jadwal: ${snapshot.error}',
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    );
                  }
                  final days = snapshot.data ?? const <DaySchedule>[];
                  if (days.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_busy, size: 64, color: scheme.outline),
                            const SizedBox(height: 16),
                            Text('Jadwal belum tersedia untuk ${_source.label}',
                                style: Theme.of(context).textTheme.titleMedium),
                          ],
                        ),
                      ),
                    );
                  }
                  final today = _todayName();
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: days.length,
                    itemBuilder: (context, i) {
                      final day = days[i];
                      final isToday = day.day == today;
                      return Card(
                        color: isToday ? scheme.primaryContainer : null,
                        child: ExpansionTile(
                          title: Row(
                            children: [
                              if (isToday)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Icon(Icons.today, size: 18),
                                ),
                              Text(day.day, style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              Text('${day.entries.length} anime',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: isToday ? scheme.onPrimaryContainer : scheme.outline)),
                            ],
                          ),
                          initiallyExpanded: isToday,
                          children: day.entries.map((e) {
                            return ListTile(
                              leading: const Icon(Icons.tv, size: 18),
                              title: Text(e.animeTitle),
                              onTap: () => _goToAnime(context, e.animeUrl),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _goToAnime(BuildContext context, String? url) {
    if (url == null) return;
    // Buat instance Anime minimal untuk navigasi
    final slug = Uri.parse(url).pathSegments.lastOrNull;
    final anime = _MinimalAnime(source: _source, slug: slug ?? url, url: url);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailScreen(anime: anime)),
    );
  }

  String _todayName() {
    final wd = DateTime.now().weekday;
    const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    return days[wd - 1];
  }
}

class _MinimalAnime extends Anime {
  _MinimalAnime({
    required SourceId source,
    required String slug,
    required String url,
  }) : super(
          id: Anime.makeId(source, slug),
          source: source,
          title: slug,
          slug: slug,
          url: url,
        );
}
