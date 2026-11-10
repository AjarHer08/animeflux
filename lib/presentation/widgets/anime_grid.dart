/// Grid anime responsif (2 kolom di mobile, 3-4 di tablet).
library;

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../data/models/anime.dart';
import 'anime_card.dart';

class AnimeGrid extends StatelessWidget {
  final List<Anime> animes;
  final void Function(Anime) onTap;
  final ScrollController? controller;
  final bool shrinkWrap;
  final EdgeInsets? padding;

  const AnimeGrid({
    super.key,
    required this.animes,
    required this.onTap,
    this.controller,
    this.shrinkWrap = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width < 600 ? 2 : (width < 900 ? 3 : 4);
    return MasonryGridView.count(
      controller: controller,
      shrinkWrap: shrinkWrap,
      padding: padding ?? const EdgeInsets.fromLTRB(16, 8, 16, 16),
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      itemCount: animes.length,
      itemBuilder: (context, i) {
        final a = animes[i];
        return AnimeCard(
          anime: a,
          onTap: () => onTap(a),
        );
      },
    );
  }
}
